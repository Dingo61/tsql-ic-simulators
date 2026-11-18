CREATE OR ALTER PROCEDURE dbo.SimulateLM741OpAmp
    @Topology VARCHAR(25) = 'NON_INVERTING', -- 'NON_INVERTING', 'INVERTING', 'FOLLOWER', 'COMPARATOR'
    @Vcc FLOAT = 15.0,                       -- Positive Supply Rail (+V)
    @Vee FLOAT = -15.0,                      -- Negative Supply Rail (-V)
    @Rin_Ohms FLOAT = 1000.0,                -- Input Resistor R1 / Rin (Ohms)
    @Rf_Ohms FLOAT = 4700.0,                 -- Feedback Resistor Rf (Ohms)
    @Vref_V FLOAT = 0.0,                     -- Reference Voltage (for Comparator mode)
    @Waveform VARCHAR(20) = 'SINE',          -- 'SINE', 'TRIANGLE', 'SQUARE'
    @Vin_Amplitude_V FLOAT = 2.0,            -- Peak Input Amplitude (V)
    @Vin_Offset_V FLOAT = 0.0,               -- DC Offset (V)
    @SignalFreq_Hz FLOAT = 1000.0,           -- Input Signal Frequency (Hz)
    @SlewRate_V_us FLOAT = 0.5,              -- LM741 Typical Slew Rate = 0.5 V/µs
    @EnableSlewLimit BIT = 1,                -- 1 = Realistic Slew Rate Limiting, 0 = Ideal Instant Slew
    @TimeStep_us FLOAT = 2.0,                -- Time step in Microseconds (µs)
    @TotalSteps INT = 1000                   -- Total simulation steps
AS
BEGIN
    SET NOCOUNT ON;

    -- LM741 output saturates ~1.5V inside the supply rails
    DECLARE @Sat_High FLOAT = @Vcc - 1.5;
    DECLARE @Sat_Low FLOAT = @Vee + 1.5;
    IF @Sat_High < @Sat_Low SET @Sat_High = @Sat_Low;

    -- Closed-loop voltage gain
    DECLARE @Gain FLOAT = CASE 
        WHEN @Topology = 'NON_INVERTING' THEN 1.0 + (@Rf_Ohms / NULLIF(@Rin_Ohms, 0))
        WHEN @Topology = 'INVERTING'     THEN -(@Rf_Ohms / NULLIF(@Rin_Ohms, 0))
        WHEN @Topology = 'FOLLOWER'      THEN 1.0
        ELSE 100000.0 -- Open-loop gain (~100,000 V/V) for Comparator mode
    END;

    -- Maximum voltage change allowed per time step (V/µs * µs)
    DECLARE @Max_DeltaV FLOAT = @SlewRate_V_us * @TimeStep_us;
    DECLARE @Period_us FLOAT = 1000000.0 / NULLIF(@SignalFreq_Hz, 0);
    DECLARE @TwoPi FLOAT = 2.0 * PI();

    -- Step 1: Generate Input Signal (Vin) and Ideal Saturated Output (Vout_Target)
    WITH SignalGen AS (
        SELECT 
            0 AS StepNum,
            CAST(0.0 AS FLOAT) AS Time_us
        UNION ALL
        SELECT 
            StepNum + 1,
            Time_us + @TimeStep_us
        FROM SignalGen
        WHERE StepNum < @TotalSteps
    ),
    IdealTransfer AS (
        SELECT 
            StepNum,
            Time_us,
            -- Synthesize Input Waveform Vin(t)
            @Vin_Offset_V + @Vin_Amplitude_V * (
                CASE 
                    WHEN @Waveform = 'SINE' THEN 
                        SIN(@TwoPi * @SignalFreq_Hz * (Time_us / 1000000.0))
                    WHEN @Waveform = 'SQUARE' THEN 
                        CASE WHEN SIN(@TwoPi * @SignalFreq_Hz * (Time_us / 1000000.0)) >= 0 THEN 1.0 ELSE -1.0 END
                    WHEN @Waveform = 'TRIANGLE' THEN 
                        (2.0 / PI()) * ASIN(SIN(@TwoPi * @SignalFreq_Hz * (Time_us / 1000000.0)))
                    ELSE 0.0
                END
            ) AS Vin_V
        FROM SignalGen
    ),
    ClampedTransfer AS (
        SELECT 
            StepNum,
            Time_us,
            Vin_V,
            -- Calculate raw amplified voltage before rail saturation
            CASE 
                WHEN @Topology = 'COMPARATOR' THEN (Vin_V - @Vref_V) * @Gain
                ELSE Vin_V * @Gain
            END AS Vout_Unclamped
        FROM IdealTransfer
    ),
    TargetOutput AS (
        SELECT 
            StepNum,
            Time_us,
            Vin_V,
            -- Apply Supply-Rail Clipping (+Vcc - 1.5V to -Vee + 1.5V)
            CASE 
                WHEN Vout_Unclamped > @Sat_High THEN @Sat_High
                WHEN Vout_Unclamped < @Sat_Low  THEN @Sat_Low
                ELSE Vout_Unclamped
            END AS Vout_Ideal_Clipped,
            CASE 
                WHEN Vout_Unclamped > @Sat_High OR Vout_Unclamped < @Sat_Low THEN 1 
                ELSE 0 
            END AS Is_Clipped
        FROM ClampedTransfer
    ),
    -- Step 2: Apply Slew-Rate Limiting across consecutive time steps (dV/dt <= SlewRate)
    SlewCTE AS (
        SELECT 
            StepNum,
            Time_us,
            Vin_V,
            Vout_Ideal_Clipped,
            Is_Clipped,
            Vout_Ideal_Clipped AS Vout_Actual,
            0 AS Is_Slew_Limited
        FROM TargetOutput
        WHERE StepNum = 0

        UNION ALL

        SELECT 
            t.StepNum,
            t.Time_us,
            t.Vin_V,
            t.Vout_Ideal_Clipped,
            t.Is_Clipped,
            CASE 
                WHEN @EnableSlewLimit = 0 THEN t.Vout_Ideal_Clipped
                WHEN (t.Vout_Ideal_Clipped - s.Vout_Actual) > @Max_DeltaV THEN s.Vout_Actual + @Max_DeltaV
                WHEN (t.Vout_Ideal_Clipped - s.Vout_Actual) < -@Max_DeltaV THEN s.Vout_Actual - @Max_DeltaV
                ELSE t.Vout_Ideal_Clipped
            END AS Vout_Actual,
            CASE 
                WHEN @EnableSlewLimit = 1 AND ABS(t.Vout_Ideal_Clipped - s.Vout_Actual) > @Max_DeltaV THEN 1
                ELSE 0
            END AS Is_Slew_Limited
        FROM TargetOutput t
        INNER JOIN SlewCTE s ON t.StepNum = s.StepNum + 1
    )
    SELECT 
        StepNum,
        ROUND(Time_us, 2) AS Time_us,
        ROUND(Vin_V, 4) AS Vin_V,
        ROUND(Vout_Ideal_Clipped, 4) AS Vout_Ideal_V,
        ROUND(Vout_Actual, 4) AS Vout_Actual_V,
        @Sat_High AS Sat_High_V,
        @Sat_Low AS Sat_Low_V,
        Is_Clipped,
        Is_Slew_Limited
    FROM SlewCTE
    OPTION (MAXRECURSION 32767);
END;
GO
