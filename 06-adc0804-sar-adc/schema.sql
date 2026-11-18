CREATE OR ALTER PROCEDURE dbo.SimulateADC0804
    @Vcc FLOAT = 5.0,                   -- Supply & Full-Scale Reference Voltage Vref (Volts)
    @Waveform VARCHAR(20) = 'SINE',     -- 'SINE', 'TRIANGLE', 'RAMP'
    @Vin_Amplitude_V FLOAT = 2.2,       -- Peak AC Amplitude (Volts)
    @Vin_Offset_V FLOAT = 2.5,          -- DC Bias Offset (Volts, centered at 2.5V for 0..5V ADC)
    @SignalFreq_Hz FLOAT = 50.0,        -- Analog Input Frequency (Hz)
    @SampleRate_Hz FLOAT = 1000.0,      -- ADC Conversion Start Rate (Samples/sec)
    @TotalSamples INT = 40              -- Number of complete 8-bit conversions to simulate
AS
BEGIN
    SET NOCOUNT ON;

    -- Each 8-bit SAR conversion requires 8 clock ticks (Bit 7 down to Bit 0)
    DECLARE @ClocksPerSample INT = 8;
    DECLARE @TotalTicks INT = @TotalSamples * @ClocksPerSample;
    DECLARE @SamplePeriod_ms FLOAT = 1000.0 / NULLIF(@SampleRate_Hz, 0);
    DECLARE @ClockPeriod_ms FLOAT = @SamplePeriod_ms / @ClocksPerSample;
    DECLARE @LSB_V FLOAT = @Vcc / 256.0; -- 1 LSB step size (~19.53 mV at 5.0V)
    DECLARE @TwoPi FLOAT = 2.0 * PI();

    -- Step 1: Generate Clock Ticks & Sample-and-Hold Analog Voltages
    WITH TickGen AS (
        SELECT 
            0 AS TickNum,
            0 AS SampleIdx,
            0 AS BitStep, -- 0..7 within each conversion (maps to Bit 7..0)
            CAST(0.0 AS FLOAT) AS Time_ms
        UNION ALL
        SELECT 
            TickNum + 1,
            (TickNum + 1) / @ClocksPerSample,
            (TickNum + 1) % @ClocksPerSample,
            (TickNum + 1) * @ClockPeriod_ms
        FROM TickGen
        WHERE TickNum < @TotalTicks - 1
    ),
    AnalogInput AS (
        SELECT 
            TickNum,
            SampleIdx,
            BitStep,
            Time_ms,
            -- Continuous Analog Input Vin(t) clamped to 0..Vcc input pins (Vin+ - Vin-)
            CASE 
                WHEN Raw_Vin > @Vcc THEN @Vcc
                WHEN Raw_Vin < 0.0  THEN 0.0
                ELSE Raw_Vin
            END AS Vin_Continuous_V
        FROM (
            SELECT 
                TickNum,
                SampleIdx,
                BitStep,
                Time_ms,
                @Vin_Offset_V + @Vin_Amplitude_V * (
                    CASE 
                        WHEN @Waveform = 'SINE' THEN 
                            SIN(@TwoPi * @SignalFreq_Hz * (Time_ms / 1000.0))
                        WHEN @Waveform = 'TRIANGLE' THEN 
                            (2.0 / PI()) * ASIN(SIN(@TwoPi * @SignalFreq_Hz * (Time_ms / 1000.0)))
                        WHEN @Waveform = 'RAMP' THEN 
                            2.0 * (((Time_ms / 1000.0) * @SignalFreq_Hz) - FLOOR((Time_ms / 1000.0) * @SignalFreq_Hz)) - 1.0
                        ELSE 0.0
                    END
                ) AS Raw_Vin
            FROM TickGen
        ) sub
    ),
    -- Latch the Sample-and-Hold voltage at BitStep = 0 of every conversion cycle
    SampleHold AS (
        SELECT 
            TickNum,
            SampleIdx,
            BitStep,
            Time_ms,
            Vin_Continuous_V,
            FIRST_VALUE(Vin_Continuous_V) OVER (PARTITION BY SampleIdx ORDER BY BitStep ASC) AS Vin_Held_V,
            (7 - BitStep) AS Bit_Position,
            CAST(POWER(2, 7 - BitStep) AS INT) AS Bit_Weight
        FROM AnalogInput
    ),
    -- Step 2: Recursive 8-Step SAR Binary Search Engine
    SAR_CTE AS (
        -- Anchor Member (Tick 0: Test Bit 7 = 128 -> Vref/2)
        SELECT 
            TickNum,
            SampleIdx,
            BitStep,
            Time_ms,
            Vin_Continuous_V,
            Vin_Held_V,
            Bit_Position,
            Bit_Weight,
            Bit_Weight AS Trial_Code,
            CAST(Bit_Weight * @LSB_V AS FLOAT) AS Trial_DAC_V,
            CASE WHEN Vin_Held_V >= (Bit_Weight * @LSB_V) THEN 1 ELSE 0 END AS Comp_Keep_Bit,
            CASE WHEN Vin_Held_V >= (Bit_Weight * @LSB_V) THEN Bit_Weight ELSE 0 END AS SAR_Accum_Code
        FROM SampleHold
        WHERE TickNum = 0

        UNION ALL

        -- Recursive Member (Step through Bit 6..0, then reset SAR on next SampleIdx)
        SELECT 
            s.TickNum,
            s.SampleIdx,
            s.BitStep,
            s.Time_ms,
            s.Vin_Continuous_V,
            s.Vin_Held_V,
            s.Bit_Position,
            s.Bit_Weight,

            -- Trial Code: If new conversion (BitStep = 0), start fresh with 128; else add Bit_Weight to accumulated SAR
            CASE 
                WHEN s.BitStep = 0 THEN s.Bit_Weight
                ELSE c.SAR_Accum_Code + s.Bit_Weight
            END AS Trial_Code,

            -- Internal R-2R Ladder DAC Voltage for Trial Code
            CAST((CASE WHEN s.BitStep = 0 THEN s.Bit_Weight ELSE c.SAR_Accum_Code + s.Bit_Weight END) * @LSB_V AS FLOAT) AS Trial_DAC_V,

            -- Internal Comparator Output: 1 if Held Analog Voltage >= Internal DAC Voltage
            CASE 
                WHEN s.Vin_Held_V >= ((CASE WHEN s.BitStep = 0 THEN s.Bit_Weight ELSE c.SAR_Accum_Code + s.Bit_Weight END) * @LSB_V) THEN 1 
                ELSE 0 
            END AS Comp_Keep_Bit,

            -- Updated SAR Register after Comparator decision
            CASE 
                WHEN s.BitStep = 0 THEN 
                    CASE WHEN s.Vin_Held_V >= (s.Bit_Weight * @LSB_V) THEN s.Bit_Weight ELSE 0 END
                ELSE 
                    c.SAR_Accum_Code + (CASE WHEN s.Vin_Held_V >= ((c.SAR_Accum_Code + s.Bit_Weight) * @LSB_V) THEN s.Bit_Weight ELSE 0 END)
            END AS SAR_Accum_Code

        FROM SampleHold s
        INNER JOIN SAR_CTE c ON s.TickNum = c.TickNum + 1
    ),
    -- Step 3: Latch Final 8-Bit Output on BitStep = 7 (INTR / End-of-Conversion)
    LatchedOutput AS (
        SELECT 
            *,
            CASE WHEN BitStep = 7 THEN 0 ELSE 1 END AS INTR_Pin5_ActiveLow,
            MAX(CASE WHEN BitStep = 7 THEN SAR_Accum_Code ELSE NULL END) OVER (PARTITION BY SampleIdx) AS Final_Digital_Code
        FROM SAR_CTE
    )
    SELECT 
        TickNum,
        SampleIdx,
        BitStep,
        Bit_Position AS Testing_Bit,
        ROUND(Time_ms, 3) AS Time_ms,
        ROUND(Vin_Continuous_V, 4) AS Vin_Analog_V,
        ROUND(Vin_Held_V, 4) AS Vin_SampleHold_V,
        Trial_Code,
        ROUND(Trial_DAC_V, 4) AS Internal_DAC_V,
        Comp_Keep_Bit,
        SAR_Accum_Code AS SAR_Register_Dec,
        Final_Digital_Code AS Output_Byte_Dec,
        ROUND(Final_Digital_Code * @LSB_V, 4) AS Reconstructed_V,
        ROUND(Vin_Held_V - (Final_Digital_Code * @LSB_V), 4) AS Quantization_Error_V,
        INTR_Pin5_ActiveLow * @Vcc AS INTR_Pin5_V,
        -- Parallel Output Pins DB7 (MSB) down to DB0 (LSB)
        CASE WHEN (Final_Digital_Code & 128) > 0 THEN 1 ELSE 0 END AS DB7,
        CASE WHEN (Final_Digital_Code & 64)  > 0 THEN 1 ELSE 0 END AS DB6,
        CASE WHEN (Final_Digital_Code & 32)  > 0 THEN 1 ELSE 0 END AS DB5,
        CASE WHEN (Final_Digital_Code & 16)  > 0 THEN 1 ELSE 0 END AS DB4,
        CASE WHEN (Final_Digital_Code & 8)   > 0 THEN 1 ELSE 0 END AS DB3,
        CASE WHEN (Final_Digital_Code & 4)   > 0 THEN 1 ELSE 0 END AS DB2,
        CASE WHEN (Final_Digital_Code & 2)   > 0 THEN 1 ELSE 0 END AS DB1,
        CASE WHEN (Final_Digital_Code & 1)   > 0 THEN 1 ELSE 0 END AS DB0
    FROM LatchedOutput
    ORDER BY TickNum ASC
    OPTION (MAXRECURSION 32767);
END;
GO
