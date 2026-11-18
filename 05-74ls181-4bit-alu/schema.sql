CREATE OR ALTER PROCEDURE dbo.Simulate74LS181ALU
    @Input_A INT = 9,            -- 4-bit Operand A (0..15)
    @Input_B INT = 5,            -- 4-bit Operand B (0..15)
    @Select_S INT = 9,           -- 4-bit Function Select S3..S0 (0..15)
    @Mode_M BIT = 0,             -- 0 = Arithmetic Mode (with Carry), 1 = Logic Mode (no Carry)
    @Carry_In BIT = 0            -- Active-High Carry In (Cn: 0 or 1)
AS
BEGIN
    SET NOCOUNT ON;

    -- Clamp inputs to valid 4-bit unsigned range (0..15)
    DECLARE @A_Sel INT = (@Input_A & 15);
    DECLARE @B_Sel INT = (@Input_B & 15);
    DECLARE @S INT = (@Select_S & 15);
    DECLARE @Cin INT = CAST(@Carry_In AS INT);

    -- Opcode Metadata Lookup Table (Active-High Data Specification)
    DECLARE @Opcodes TABLE (
        S_Code INT PRIMARY KEY,
        S_Bin CHAR(4),
        Logic_Expr VARCHAR(40),
        Arith_Expr_Cin0 VARCHAR(40),
        Arith_Expr_Cin1 VARCHAR(40)
    );

    INSERT INTO @Opcodes (S_Code, S_Bin, Logic_Expr, Arith_Expr_Cin0, Arith_Expr_Cin1) VALUES
    (0,  '0000', 'F = NOT A',               'F = A',                      'F = A + 1'),
    (1,  '0001', 'F = NOT (A OR B)',        'F = A OR B',                 'F = (A OR B) + 1'),
    (2,  '0010', 'F = (NOT A) AND B',       'F = A OR (NOT B)',           'F = (A OR (NOT B)) + 1'),
    (3,  '0011', 'F = 0 (Logic Zero)',      'F = -1 (2s Comp: 1111)',     'F = 0'),
    (4,  '0100', 'F = NOT (A AND B)',       'F = A + (A AND NOT B)',      'F = A + (A AND NOT B) + 1'),
    (5,  '0101', 'F = NOT B',               'F = (A OR B) + (A AND NOT B)','F = (A OR B) + (A AND NOT B) + 1'),
    (6,  '0110', 'F = A XOR B',             'F = A - B - 1',              'F = A - B (Subtract)'),
    (7,  '0111', 'F = A AND (NOT B)',       'F = (A AND NOT B) - 1',      'F = A AND (NOT B)'),
    (8,  '1000', 'F = (NOT A) OR B',        'F = A + (A AND B)',          'F = A + (A AND B) + 1'),
    (9,  '1001', 'F = NOT (A XOR B)',       'F = A + B (Add)',            'F = A + B + 1'),
    (10, '1010', 'F = B',                   'F = (A OR NOT B) + (A AND B)','F = (A OR NOT B) + (A AND B) + 1'),
    (11, '1011', 'F = A AND B',             'F = (A AND B) - 1',          'F = A AND B'),
    (12, '1100', 'F = 1 (Logic One: 1111)', 'F = A + A (Shift Left)',     'F = A + A + 1'),
    (13, '1101', 'F = A OR (NOT B)',        'F = (A OR B) + A',           'F = (A OR B) + A + 1'),
    (14, '1110', 'F = A OR B',              'F = (A OR NOT B) + A',       'F = (A OR NOT B) + A + 1'),
    (15, '1111', 'F = A',                   'F = A - 1 (Decrement)',      'F = A');

    -- Generate full 4-bit state space (0..15) using a set-based Values constructor
    WITH Nibble AS (
        SELECT V FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15)) AS T(V)
    ),
    -- Evaluate all 256 (A, B) combinations simultaneously in one relational pass
    TruthMatrix AS (
        SELECT 
            a.V AS A,
            b.V AS B,
            (~a.V) & 15 AS NotA,
            (~b.V) & 15 AS NotB,
            CASE 
                -- MODE M = 1: Pure Bitwise Logic Operations (No Carry)
                WHEN @Mode_M = 1 THEN
                    CASE @S
                        WHEN 0  THEN (~a.V) & 15
                        WHEN 1  THEN (~(a.V | b.V)) & 15
                        WHEN 2  THEN ((~a.V) & b.V) & 15
                        WHEN 3  THEN 0
                        WHEN 4  THEN (~(a.V & b.V)) & 15
                        WHEN 5  THEN (~b.V) & 15
                        WHEN 6  THEN (a.V ^ b.V) & 15
                        WHEN 7  THEN (a.V & (~b.V)) & 15
                        WHEN 8  THEN ((~a.V) | b.V) & 15
                        WHEN 9  THEN (~(a.V ^ b.V)) & 15
                        WHEN 10 THEN b.V
                        WHEN 11 THEN (a.V & b.V) & 15
                        WHEN 12 THEN 15
                        WHEN 13 THEN (a.V | (~b.V)) & 15
                        WHEN 14 THEN (a.V | b.V) & 15
                        WHEN 15 THEN a.V
                    END
                -- MODE M = 0: Arithmetic Operations (Evaluated in signed/wider int to capture Carry Out)
                ELSE
                    CASE @S
                        WHEN 0  THEN a.V + @Cin
                        WHEN 1  THEN (a.V | b.V) + @Cin
                        WHEN 2  THEN (a.V | ((~b.V) & 15)) + @Cin
                        WHEN 3  THEN -1 + @Cin
                        WHEN 4  THEN a.V + (a.V & ((~b.V) & 15)) + @Cin
                        WHEN 5  THEN (a.V | b.V) + (a.V & ((~b.V) & 15)) + @Cin
                        WHEN 6  THEN a.V - b.V - 1 + @Cin
                        WHEN 7  THEN (a.V & ((~b.V) & 15)) - 1 + @Cin
                        WHEN 8  THEN a.V + (a.V & b.V) + @Cin
                        WHEN 9  THEN a.V + b.V + @Cin
                        WHEN 10 THEN (a.V | ((~b.V) & 15)) + (a.V & b.V) + @Cin
                        WHEN 11 THEN (a.V & b.V) - 1 + @Cin
                        WHEN 12 THEN a.V + a.V + @Cin
                        WHEN 13 THEN (a.V | b.V) + a.V + @Cin
                        WHEN 14 THEN (a.V | ((~b.V) & 15)) + a.V + @Cin
                        WHEN 15 THEN a.V - 1 + @Cin
                    END
            END AS Raw_Result
        FROM Nibble a
        CROSS JOIN Nibble b
    )
    SELECT 
        t.A AS Operand_A,
        t.B AS Operand_B,
        CASE WHEN t.A = @A_Sel AND t.B = @B_Sel THEN 1 ELSE 0 END AS Is_Selected_Row,
        -- Mask output F3..F0 to 4 bits (0..15)
        (t.Raw_Result & 15) AS Output_F,
        -- Carry Out (Cn+4): In Logic mode forced to 0; in Arithmetic mode detects overflow/borrow
        CASE 
            WHEN @Mode_M = 1 THEN 0
            WHEN t.Raw_Result > 15 OR t.Raw_Result < 0 THEN 1 
            ELSE 0 
        END AS Carry_Out,
        -- A = B Open-Collector Comparator Pin (HIGH when all 4 output bits F3..F0 are 1, i.e. F = 15)
        CASE WHEN (t.Raw_Result & 15) = 15 THEN 1 ELSE 0 END AS A_Equals_B_Pin,
        -- Individual Output Bits F3 (MSB) down to F0 (LSB)
        CASE WHEN (t.Raw_Result & 8) > 0 THEN 1 ELSE 0 END AS F3,
        CASE WHEN (t.Raw_Result & 4) > 0 THEN 1 ELSE 0 END AS F2,
        CASE WHEN (t.Raw_Result & 2) > 0 THEN 1 ELSE 0 END AS F1,
        CASE WHEN (t.Raw_Result & 1) > 0 THEN 1 ELSE 0 END AS F0,
        -- Opcode Metadata
        o.S_Bin AS Select_Binary,
        CASE 
            WHEN @Mode_M = 1 THEN o.Logic_Expr
            WHEN @Cin = 0 THEN o.Arith_Expr_Cin0
            ELSE o.Arith_Expr_Cin1
        END AS Active_Operation
    FROM TruthMatrix t
    CROSS JOIN @Opcodes o
    WHERE o.S_Code = @S
    ORDER BY t.A ASC, t.B ASC;
END;
GO
