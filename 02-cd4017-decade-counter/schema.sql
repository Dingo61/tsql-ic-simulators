CREATE OR ALTER PROCEDURE dbo.SimulateCD4017Counter
@ClockSource VARCHAR (20)='NE555', -- 'NE555' (chained) or 'SQUARE' (ideal clock)
@Vcc FLOAT=5.0, -- Supply Voltage (Volts)
-- NE555 Clock Source Parameters (used when @ClockSource = 'NE555')
@R1 FLOAT=1000.0, @R2 FLOAT=10000.0, @C_uF FLOAT=10.0, -- Ideal Square Wave Parameter (used when @ClockSource = 'SQUARE')
@ClockFreq_Hz FLOAT=10.0, -- CD4017 Control Pins (CSV timestamps in ms)
@ResetEvents_ms VARCHAR (MAX)='', -- Pin 15 (MR): Active-High asynchronous reset
@InhibitEvents_ms VARCHAR (MAX)='', -- Pin 13 (CE): Active-High clock freeze
@ControlPulse_ms FLOAT=25.0, -- Duration of Reset / Inhibit pulses
-- Simulation Resolution
@TimeStep_ms FLOAT=1.0, @TotalSteps INT=600
AS
BEGIN
    SET NOCOUNT ON;
    -- Parse Reset (Pin 15) and Clock Inhibit (Pin 13) events
    DECLARE @Resets TABLE (
        Start_ms FLOAT);
    DECLARE @Inhibits TABLE (
        Start_ms FLOAT);
    INSERT INTO @Resets (
        Start_ms
    )
    SELECT TRY_CAST (value AS FLOAT)
    FROM   STRING_SPLIT (@ResetEvents_ms, ',')
    WHERE  TRY_CAST (value AS FLOAT) IS NOT NULL;
    INSERT INTO @Inhibits (
        Start_ms
    )
    SELECT TRY_CAST (value AS FLOAT)
    FROM   STRING_SPLIT (@InhibitEvents_ms, ',')
    WHERE  TRY_CAST (value AS FLOAT) IS NOT NULL;
    -- Base SI Conversions for NE555 mode
    DECLARE @C AS FLOAT = @C_uF / 1000000.0;
    DECLARE @dt AS FLOAT = @TimeStep_ms / 1000.0;
    DECLARE @V_upper AS FLOAT = (2.0 / 3.0) * @Vcc;
    DECLARE @V_lower AS FLOAT = (1.0 / 3.0) * @Vcc;
    DECLARE @Alpha_Charge AS FLOAT = 1.0 - EXP(-@dt / ((@R1 + @R2) * @C));
    DECLARE @Alpha_Discharge AS FLOAT = 1.0 - EXP(-@dt / (@R2 * @C));
    DECLARE @HalfPeriod_ms AS FLOAT = 500.0 / NULLIF (@ClockFreq_Hz, 0);
    -- Step 1: Generate the Clock Waveform (either NE555 RC physics or Ideal Square Wave)
    WITH   ClockCTE
    AS     (SELECT 0 AS StepNum,
                   CAST (0.0 AS FLOAT) AS Time_ms,
                   CAST (0.0 AS FLOAT) AS V_cap,
                   1 AS Clk_State,
                   0 AS Discharge_On
            UNION ALL
            SELECT StepNum + 1,
                   Time_ms + @TimeStep_ms,
                   CASE WHEN @ClockSource = 'SQUARE' THEN CAST (0.0 AS FLOAT) WHEN Discharge_On = 0 THEN V_cap + (@Vcc - V_cap) * @Alpha_Charge ELSE V_cap + (0.0 - V_cap) * @Alpha_Discharge END,
                   CASE WHEN @ClockSource = 'SQUARE' THEN CASE WHEN CAST (FLOOR((Time_ms + @TimeStep_ms) / @HalfPeriod_ms) AS BIGINT) % 2 = 0 THEN 1 ELSE 0 END ELSE CASE WHEN (CASE WHEN Discharge_On = 0 THEN V_cap + (@Vcc - V_cap) * @Alpha_Charge ELSE V_cap + (0.0 - V_cap) * @Alpha_Discharge END) >= @V_upper THEN 0 WHEN (CASE WHEN Discharge_On = 0 THEN V_cap + (@Vcc - V_cap) * @Alpha_Charge ELSE V_cap + (0.0 - V_cap) * @Alpha_Discharge END) <= @V_lower THEN 1 ELSE Clk_State END END,
                   CASE WHEN @ClockSource = 'SQUARE' THEN 0 WHEN (CASE WHEN Discharge_On = 0 THEN V_cap + (@Vcc - V_cap) * @Alpha_Charge ELSE V_cap + (0.0 - V_cap) * @Alpha_Discharge END) >= @V_upper THEN 1 WHEN (CASE WHEN Discharge_On = 0 THEN V_cap + (@Vcc - V_cap) * @Alpha_Charge ELSE V_cap + (0.0 - V_cap) * @Alpha_Discharge END) <= @V_lower THEN 0 ELSE Discharge_On END
            FROM   ClockCTE
            WHERE  StepNum < @TotalSteps),
    -- Step 2: Detect Rising Edges using LAG() and evaluate Control Pins
           SignalAnalysis
    AS     (SELECT StepNum,
                   Time_ms,
                   Clk_State,
                   CASE WHEN Clk_State = 1
                             AND ISNULL(LAG(Clk_State) OVER (ORDER BY StepNum), 0) = 0 THEN 1 ELSE 0 END AS Is_Rising_Edge,
                   CASE WHEN EXISTS (SELECT 1
                                     FROM   @Resets AS r
                                     WHERE  Time_ms BETWEEN r.Start_ms AND (r.Start_ms + @ControlPulse_ms)) THEN 1 ELSE 0 END AS MR_Active,
                   CASE WHEN EXISTS (SELECT 1
                                     FROM   @Inhibits AS i
                                     WHERE  Time_ms BETWEEN i.Start_ms AND (i.Start_ms + @ControlPulse_ms)) THEN 1 ELSE 0 END AS CE_Active
            FROM   ClockCTE),
    -- Step 3: CD4017 Johnson Counter State Machine
           CounterCTE
    AS     (SELECT StepNum,
                   Time_ms,
                   Clk_State,
                   MR_Active,
                   CE_Active,
                   CASE WHEN MR_Active = 1 THEN 0 ELSE 0 END AS Count_State
            FROM   SignalAnalysis
            WHERE  StepNum = 0
            UNION ALL
            SELECT s.StepNum,
                   s.Time_ms,
                   s.Clk_State,
                   s.MR_Active,
                   s.CE_Active,
                   CASE -- Asynchronous Master Reset (Pin 15) immediately forces Q0 (Count = 0)
                   WHEN s.MR_Active = 1 THEN 0 -- Rising clock edge advances counter if Clock Inhibit (Pin 13) is LOW
                   WHEN s.Is_Rising_Edge = 1
                        AND s.CE_Active = 0 THEN (c.Count_State + 1) % 10 ELSE -- Otherwise hold state
                   c.Count_State END AS Count_State
            FROM   SignalAnalysis AS s
                   INNER JOIN
                   CounterCTE AS c
                   ON s.StepNum = c.StepNum + 1)
    SELECT -- Step 4: Decode internal state into the 10 physical output pins (Q0-Q9) & Carry Out
           StepNum,
           ROUND(Time_ms, 3) AS Time_ms,
           Clk_State * @Vcc AS Clock_In_V,
           MR_Active * @Vcc AS Reset_Pin15_V,
           CE_Active * @Vcc AS Inhibit_Pin13_V,
           Count_State AS Active_Pin_Index,
           CASE WHEN Count_State = 0 THEN @Vcc ELSE 0.0 END AS Q0_V,
           CASE WHEN Count_State = 1 THEN @Vcc ELSE 0.0 END AS Q1_V,
           CASE WHEN Count_State = 2 THEN @Vcc ELSE 0.0 END AS Q2_V,
           CASE WHEN Count_State = 3 THEN @Vcc ELSE 0.0 END AS Q3_V,
           CASE WHEN Count_State = 4 THEN @Vcc ELSE 0.0 END AS Q4_V,
           CASE WHEN Count_State = 5 THEN @Vcc ELSE 0.0 END AS Q5_V,
           CASE WHEN Count_State = 6 THEN @Vcc ELSE 0.0 END AS Q6_V,
           CASE WHEN Count_State = 7 THEN @Vcc ELSE 0.0 END AS Q7_V,
           CASE WHEN Count_State = 8 THEN @Vcc ELSE 0.0 END AS Q8_V,
           CASE WHEN Count_State = 9 THEN @Vcc ELSE 0.0 END AS Q9_V,
           -- Carry Out (Pin 12) is HIGH for counts 0..4 and LOW for counts 5..9
           CASE WHEN Count_State < 5 THEN @Vcc ELSE 0.0 END AS Carry_Out_V
    FROM   CounterCTE
    OPTION (MAXRECURSION 32767);
END