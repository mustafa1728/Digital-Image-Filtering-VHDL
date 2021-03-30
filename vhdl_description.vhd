library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

ENTITY RAM_64Kx8 IS
    PORT(
            clock : IN std_logic;
            read_enable, write_enable : IN std_logic; -- signals that enable read/write operation
            address : IN std_logic_vector(15 downto 0); -- 2^16 = 64K
            data_in : IN std_logic_vector(7 downto 0);
            data_out : OUT std_logic_vector(7 downto 0)
        );
END RAM_64Kx8;


ENTITY ROM_32x9 IS
    PORT (
            clock : IN std_logic;
            read_enable : IN std_logic; -- SIGNAL that enables read operation
            address : IN std_logic_vector(4 downto 0); -- 2^5 = 32
            data_out : OUT std_logic_vector(7 downto 0)
    );
END ROM_32x9;


ENTITY MAC IS
    PORT (
            clock : IN std_logic;
            control : IN std_logic; -- ‘0’ for initializing the sum
            data_in1, data_in2 : IN std_logic_vector(17 downto 0);
            data_out : OUT std_logic_vector(17 downto 0)
    );
END MAC;


ARCHITECTURE Artix of RAM_64Kx8 IS
    TYPE Memory_type IS array (0 to 65535) of std_logic_vector (7 downto 0);
    SIGNAL Memory_array : Memory_type;
BEGIN
    PROCESS (clock) BEGIN
        IF rising_edge (clock) THEN
            IF (read_enable = '1') THEN -- the data read IS available after the clock edge
                data_out <= Memory_array (to_integer (unsigned (address)));
            END IF;
            IF (write_enable = '1') THEN -- the data IS written on the clock edge
                Memory_array (to_integer (unsigned(address))) <= data_in;
            END IF;
        END IF;
    END PROCESS;
END Artix;


ARCHITECTURE Artix of ROM_32x9 IS
    TYPE Memory_type IS array (0 to 31) of std_logic_vector (8 downto 0);
    SIGNAL Memory_array : Memory_type;
BEGIN
    PROCESS (clock) BEGIN
        IF rising_edge (clock) THEN
            IF (read_enable = '1') THEN -- the data read IS available after the clock edge
                data_out <= Memory_array (to_integer (unsigned (address)));
            END IF;
        END IF;
    END PROCESS;
END Artix;

ARCHITECTURE Artix of MAC IS
    SIGNAL sum, product : signed (17 downto 0);
BEGIN
    data_out <= std_logic_vector (sum);
    product <= signed (data_in1) * signed (data_in2)
    PROCESS (clock) BEGIN
        IF rising_edge (clock) THEN -- sum is available after clock edge
            IF (control = '0') THEN -- initialize the sum with the first product
                sum <= std_logic_vector (product);
            ELSE -- add product to the previous sum
                sum <= std_logic_vector (product + signed (sum));
            END IF;
        END IF;
    END PROCESS;
END Artix;











ENTITY imageProcessor IS 
    PORT (  clock: IN std_logic;            -- input master clock of 100MHz
            externalSwitch : IN std_logic;  -- for toggling between smoothening and sharpening
            button : IN std_logic           -- push button for starting filtering
        );
END imageProcessor;

ARCHITECTURE imageProcessing of imageProcessor IS 
    SIGNAL row, column :  integer := 0;
    --Row, column location of the pixel from input image being considered
    SIGNAL position :  integer := 0;
    --0 to 8, indicating location in the filter coefficient matrix
    SIGNAL address_inputImage, address_filteredImage : std_logic_vector(15 downto 0);
    --These will temporarily store the addresses of inputImage and filteredImage respectively
    --when reading or writing, they are assigned to address_ram
    SIGNAL state: std_logic_vector(1 downto 0) := '00';
    --'00' is idle state
    --'01' is filtering state 
    --'10' is buffer state 
    SIGNAL subState: std_logic_vector (1 downto 0) := '00';
    --'00' is when addresses (input image pixel and filtered image pixel) are updated
    --'01' is when data is accessed
    --'10' is when data is updated
    --'11' is when next position is accessed or work is complete
    
    SIGNAL ack : bit := '1' ;
    --When filtering is complete, ack is 1

    SIGNAL read_enable_ram, write_enable_ram : IN std_logic := '0'; 
    SIGNAL address_ram : std_logic_vector(15 downto 0);
    SIGNAL data_in_ram : std_logic_vector(7 downto 0);
    SIGNAL data_out_ram : std_logic_vector(7 downto 0);
    --Input and output signals for RAM
    
    SIGNAL read_enable_rom : std_logic := '0';
    SIGNAL address_rom : std_logic_vector(4 downto 0); 
    SIGNAL data_out_rom : std_logic_vector(7 downto 0);
    --Input and output signals for ROM
    
    SIGNAL control_mac :  std_logic := '1'; 
    SIGNAL data_in1_mac , data_in2_mac : IN std_logic_vector(17 downto 0);
    SIGNAL data_out_mac : std_logic_vector(17 downto 0);
    --Input and output signals for MAC
    
    SIGNAL address_filter : integer := 0;

    

BEGIN 
    
    readWriteImage : ENTITY work.RAM_64Kx8(Artix) 
    PORT MAP(
            clock , 
            read_enable_ram, 
            write_enable_ram , 
            address_ram , 
            data_in_ram , 

            data_out_ram 
            );


    readMatrix : ENTITY work.ROM_32x9(Artix) 
    PORT MAP(
            clock , 
            read_enable_rom , 
            address_rom, 

            data_out_rom 
            );


    Multiplication : ENTITY work.MAC(Artix) 
    PORT MAP(
            clock, 
            control_mac, 
            data_in1_mac, 
            data_in2_mac, 

            data_out_mac
            );

    --This process deals with the main state transitions
    PROCESS(clock, button, externalSwitch)   
    BEGIN
        IF rising_edge (clock) THEN
            IF state = '00' THEN 
                IF button = '1' THEN 
                    read_enable_ram <= '0' ; 
                    write_enable_ram <= '0' ;
                    read_enable_rom <= '0' ; 
                    control_mac <= '0';

                    -- System will check for the switch only when the button is pressed
                    IF externalSwitch = '1' THEN 
                        address_filter <= 16; 
                    ELSE 
                        address_filter <= 0; 
                    END IF
                    state <= '01' ; 
                    ack <= '0' ; 
                    row <= 0 ; 
                    column <= 0 ; 
                    position <= 0 ;  
                END IF
            ELSE IF state = '01' THEN
                IF ack ='1' THEN 
                    state <= '10' ; 
                    subState <= '00';  
                END IF;
            ELSE IF state = '10' THEN
                IF button = '0'
                    state =< '00'
                END IF
            END IF;
        END IF;
    END PROCESS;

    
    --This process deals with the state transitions between substates in the filtering state
    PROCESS(clock)
    BEGIN
        IF rising_edge (clock) THEN 
            IF( state = '01' ) THEN 

                IF subState = '00' THEN --  addresses of input & output are updated
                    read_enable_ram <= '0' ; 
                    write_enable_ram <= '0' ;
                    read_enable_rom <= '0' ; 
                    control_mac <= '1';

                    data_in1_mac <= "000000000000000000";
                    data_in2_mac <= "000000000000000000";
                    
                    case position IS 
                        when 0 =>   address_inputImage <= 120*row + column ;
                                    address_rom <= 0 + address_filter;
                        when 1 =>   address_inputImage <= 120*row + column + 1 ; 
                                    address_rom <= 1 + address_filter;
                        when 2 =>   address_inputImage <= 120*row + column + 2 ; 
                                    address_rom <= 2 + address_filter;
                        when 3 =>   address_inputImage <= 120*(row + 1 ) + column ; 
                                    address_rom <= 3 + address_filter;
                        when 4 =>   address_inputImage <= 120*(row + 1 ) + column + 1 ; 
                                    address_rom <= 4 + address_filter;
                        when 5 =>   address_inputImage <= 120*(row + 1 ) + column + 2 ; 
                                    address_rom <= 5 + address_filter;
                        when 6 =>   address_inputImage <= 120*(row + 2 ) + column ; 
                                    address_rom <= 6 + address_filter;
                        when 7 =>   address_inputImage <= 120*(row + 2 ) + column + 1 ; 
                                    address_rom <= 7 + address_filter;
                        when 8 =>   address_inputImage <= 120*(row + 2 ) + column + 2 ; 
                                    address_rom <= 8 + address_filter;
                    END case;

                    address_filteredImage <= 118*row + column + 32768 ;     
                    -- filtered image has to be stored at addresses starting from 32768

                    subState <= '01';

                ELSE IF subState = '01' THEN --  data is accessed, and MAC operations performed
                    address_ram <= address_inputImage

                    read_enable_ram <= '1' ; 
                    write_enable_ram <= '0' ;
                    read_enable_rom <= '1' ; 
                    control_mac <= '1';

                    IF(data_out_rom(7) = 0) THEN 
                        data_in2_mac <= "00" & data_out_rom;
                    ELSE 
                        data_in2_mac <= "11" & data_out_rom; 
                    END IF;
                    
                    data_in1_mac <= "00" & data_out_ram;

                    IF position = 0 THEN 
                        control_mac <= '0'; 
                    ELSE IF position = 8 THEN
                        subState <= '10'; --update data
                    ELSE 
                        subState <= '00'; --search address
                        position <= position + 1;
                    END IF;
                ELSE IF subState = '10' THEN --  data is updated
                    address_ram <= address_filteredImage

                    read_enable_ram <= '0' ; 
                    write_enable_ram <= '1' ;
                    read_enable_rom <= '0' ; 
                    control_mac <= '1';


                    IF(data_out_mac(17) = '1' ) THEN 
                        data_in_ram  <=  "00000000";
                    ELSE
                        data_in_ram <= data_out_mac;
                    END IF;
                    subState <= '11'; -- go to next pixel
                    position = 0;

                ELSE IF subState = '11' THEN -- next pixel is accessed or ack<=1
                    -- The resolution is assumed to be 120 rows x 160 columns
                    read_enable_ram <= '0' ; 
                    write_enable_ram <= '0' ;
                    read_enable_rom <= '0' ; 
                    control_mac <= '0';

                    column <= column + 1; 
                    IF(column = 157) THEN
                        IF( row = 117 ) THEN 
                            ack <= '1' ; 
                        row <= row + 1; 
                        column <= 0 ; 
                        
                        END IF;
                    END IF; 
                    subState <= '00' ;
                END IF;
            END IF;
        END IF;     
    END PROCESS;

END imageProcessing;

