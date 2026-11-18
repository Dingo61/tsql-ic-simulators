CREATE OR ALTER PROCEDURE dbo.Simulate74HC595ShiftRegister
    @Vcc FLOAT = 5.0,                      -- Supply Voltage (Volts)
    @BitStream VARCHAR(64) = '10110101',   -- Serial bits to shift in (MSB first)
    @ClockFreq_Hz FLOAT = 10.0,            -- Shift Clock (SHCP) frequency
    @LatchMode VARCHAR(20) = 'AUTO_BYTE',  -- 'AUTO_BYTE' (latch every 8 bits) or 'MANUAL'
    @ManualLatch_ms VARCHAR(MAX) = '',     -- CSV timestamps for STCP rising edges (if MANUAL)
    @ResetEvents_ms VARCHAR(MAX) = '',     -- CSV timestamps for active-low MR (Pin 10) pulses
    @DisableEvents_ms VARCHAR(MAX) = '',   -- CSV timestamps for active-high OE (Pin 13) Hi-Z pulses
    @ControlPulse_ms FLOAT = 30.0,         -- Duration of Reset / Output Disable pulses
    @TimeStep_ms FLOAT = 2.0,              -- Simulation resolution (ms)
    @TotalSteps INT = 600                  -- Total simulation steps
AS
BEGIN
    SET NOCOUNT ON;

    -- Sanitize BitStream (keep only 0s and 1s, default to '10101010' if empty)
    DECLARE @CleanBits VARCHAR(64) = ISNULL(NULLIF(@BitStream, ''), '10101010');
    DECLARE @StreamLen INT = LEN(@CleanBits);

    -- Parse Manual Latch, Active-Low Reset (MR), and Active-High Output Disable (OE) events
    DECLARE @Latches TABLE (Start_ms FLOAT);
    DECLARE @Resets TABLE (Start_ms FLOAT);
    DECLARE @Disables TABLE (Start_ms FLOAT);

    INSERT INTO @Latches (Start_ms)
    SELECT TRY_CAST(value AS FLOAT) FROM STRING_SPLIT(@ManualLatch_ms, ',') WHERE TRY_CAST(value AS FLOAT) IS NOT NULL;

    INSERT INTO @Resets (Start_ms)
    SELECT TRY_CAST(value AS FLOAT) FROM STRING_SPLIT(@ResetEvents_ms, ',') WHERE TRY_CAST(value AS FLOAT) IS NOT NULL;

    INSERT INTO @Disables (Start_ms)
    SELECT TRY_CAST(value AS FLOAT) FROM STRING_SPLIT(@DisableEvents_ms, ',') WHERE TRY_CAST(value AS FLOAT) IS NOT NULL;

    DECLARE @HalfPeriod_ms FLOAT = 500.0 / NULLIF(@ClockFreq_Hz, 0);

    -- Step 1: Generate Shift Clock (SHCP) and Control Signals
    WITH ClockGen AS (
        SELECT 
            0 AS StepNum,
            CAST(0.0 AS FLOAT) AS Time_ms,
            0 AS SHCP_State
        UNION ALL
        SELECT 
            StepNum + 1,
            Time_ms + @TimeStep_ms,
            -- Start LOW so the first transition is a clean rising edge
            CASE WHEN CAST(FLOOR((Time_ms + @TimeStep_ms) / @HalfPeriod_ms) AS BIGINT) % 2 = 1 THEN 1 ELSE 0 END
        FROM ClockGen
        WHERE StepNum < @TotalSteps
    ),
    -- Step 2: Detect SHCP Rising Edges and evaluate Control Pins
    SignalAnalysis AS (
        SELECT 
            StepNum,
            Time_ms,
            SHCP_State,
            CASE 
                WHEN SHCP_State = 1 AND ISNULL(LAG(SHCP_State) OVER (ORDER BY StepNum), 0) = 0 THEN 1 
                ELSE 0 
            END AS SHCP_Rising,
            -- Active-Low Master Reset (MR / Pin 10): 0 = Reset active, 1 = Normal
            CASE 
                WHEN EXISTS (SELECT 1 FROM @Resets r WHERE Time_ms BETWEEN r.Start_ms AND (r.Start_ms + @ControlPulse_ms)) THEN 0 
                ELSE 1 
            END AS MR_Pin10,
            -- Active-Low Output Enable (OE / Pin 13): 1 = Outputs Disabled (Hi-Z), 0 = Outputs Enabled
            CASE 
                WHEN EXISTS (SELECT 1 FROM @Disables d WHERE Time_ms BETWEEN d.Start_ms AND (d.Start_ms + @ControlPulse_ms)) THEN 1 
                ELSE 0 
            END AS OE_Pin13,
            -- Manual Latch Pulse (STCP / Pin 12)
            CASE 
                WHEN @LatchMode = 'MANUAL' AND EXISTS (SELECT 1 FROM @Latches l WHERE Time_ms BETWEEN l.Start_ms AND (l.Start_ms + @TimeStep_ms * 1.5)) THEN 1
                ELSE 0
            END AS Manual_STCP_High
        FROM ClockGen
    ),
    -- Step 3: Dual-Register State Machine (8-bit Shift Register + 8-bit Storage Latch)
    RegisterCTE AS (
        SELECT 
            StepNum,
            Time_ms,
            SHCP_State,
            MR_Pin10,
            OE_Pin13,
            0 AS Bit_Index,
            CAST(SUBSTRING(@CleanBits, 1, 1) AS INT) AS DS_Bit,
            0 AS Shift_Reg,      -- Internal 8-bit shift register (0..255)
            0 AS Storage_Reg,    -- Output 8-bit latch register (0..255)
            0 AS STCP_State      -- Storage clock state
        FROM SignalAnalysis
        WHERE StepNum = 0

        UNION ALL

        SELECT 
            s.StepNum,
            s.Time_ms,
            s.SHCP_State,
            s.MR_Pin10,
            s.OE_Pin13,

            -- Advance bit pointer after each rising edge
            CASE 
                WHEN s.SHCP_Rising = 1 THEN (r.Bit_Index + 1) % @StreamLen
                ELSE r.Bit_Index
            END AS Bit_Index,

            -- Current Serial Data (DS / Pin 14) presented at input
            CAST(SUBSTRING(@CleanBits, (CASE WHEN s.SHCP_Rising = 1 THEN (r.Bit_Index + 1) % @StreamLen ELSE r.Bit_Index END) + 1, 1) AS INT) AS DS_Bit,

            -- Update Internal Shift Register (Bitwise left shift + OR new bit, masked to 8 bits)
            CASE 
                WHEN s.MR_Pin10 = 0 THEN 0
                WHEN s.SHCP_Rising = 1 THEN ((r.Shift_Reg * 2) & 255) | r.DS_Bit
                ELSE r.Shift_Reg
            END AS Shift_Reg,

            -- Update Storage Register (Latches Shift_Reg on STCP rising edge)
            CASE 
                WHEN @LatchMode = 'AUTO_BYTE' AND s.SHCP_Rising = 1 AND ((r.Bit_Index + 1) % 8 = 0) THEN 
                    CASE WHEN s.MR_Pin10 = 0 THEN 0 ELSE ((r.Shift_Reg * 2) & 255) | r.DS_Bit END
                WHEN @LatchMode = 'MANUAL' AND s.Manual_STCP_High = 1 AND r.STCP_State = 0 THEN 
                    CASE WHEN s.MR_Pin10 = 0 THEN 0 ELSE r.Shift_Reg END
                ELSE r.Storage_Reg
            END AS Storage_Reg,

            -- Track STCP Pin 12 state for plotting
            CASE 
                WHEN @LatchMode = 'AUTO_BYTE' AND s.SHCP_Rising = 1 AND ((r.Bit_Index + 1) % 8 = 0) THEN 1
                WHEN @LatchMode = 'MANUAL' AND s.Manual_STCP_High = 1 THEN 1
                ELSE 0
            END AS STCP_State

        FROM SignalAnalysis s
        INNER JOIN RegisterCTE r ON s.StepNum = r.StepNum + 1
    )
    -- Step 4: Extract individual Q0..Q7 output pins using Bitwise AND (&)
    SELECT 
        StepNum,
        ROUND(Time_ms, 3) AS Time_ms,
        DS_Bit * @Vcc AS DS_Pin14_V,
        SHCP_State * @Vcc AS SHCP_Pin11_V,
        STCP_State * @Vcc AS STCP_Pin12_V,
        MR_Pin10 * @Vcc AS MR_Pin10_V,
        OE_Pin13 * @Vcc AS OE_Pin13_V,
        Shift_Reg AS Internal_Shift_Dec,
        Storage_Reg AS Latched_Output_Dec,
        -- Serial Cascade Output Q7' (Pin 9) reflects Bit 7 of internal shift register
        CASE WHEN (Shift_Reg & 128) > 0 THEN @Vcc ELSE 0.0 END AS Q7_Prime_Pin9_V,
        -- Parallel Outputs Q0..Q7 (Return NULL when OE is HIGH to represent Tri-State Hi-Z)
        CASE WHEN OE_Pin13 = 1 THEN NULL WHEN (Storage_Reg & 1) > 0 THEN @Vcc ELSE 0.0 END AS Q0_V,
        CASE WHEN OE_Pin13 = 1 THEN NULL WHEN (Storage_Reg & 2) > 0 THEN @Vcc ELSE 0.0 END AS Q1_V,
        CASE WHEN OE_Pin13 = 1 THEN NULL WHEN (Storage_Reg & 4) > 0 THEN @Vcc ELSE 0.0 END AS Q2_V,
        CASE WHEN OE_Pin13 = 1 THEN NULL WHEN (Storage_Reg & 8) > 0 THEN @Vcc ELSE 0.0 END AS Q3_V,
        CASE WHEN OE_Pin13 = 1 THEN NULL WHEN (Storage_Reg & 16) > 0 THEN @Vcc ELSE 0.0 END AS Q4_V,
        CASE WHEN OE_Pin13 = 1 THEN NULL WHEN (Storage_Reg & 32) > 0 THEN @Vcc ELSE 0.0 END AS Q5_V,
        CASE WHEN OE_Pin13 = 1 THEN NULL WHEN (Storage_Reg & 64) > 0 THEN @Vcc ELSE 0.0 END AS Q6_V,
        CASE WHEN OE_Pin13 = 1 THEN NULL WHEN (Storage_Reg & 128) > 0 THEN @Vcc ELSE 0.0 END AS Q7_V
    FROM RegisterCTE
    OPTION (MAXRECURSION 32767);
END;
GO
