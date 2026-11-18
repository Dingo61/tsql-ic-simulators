-- Run this script in your SQL Server database to create the simulation stored procedure.

CREATE OR ALTER PROCEDURE dbo.Simulate555Timer
    @Mode VARCHAR(20) = 'ASTABLE',         -- 'ASTABLE' or 'BISTABLE'
    @Vcc FLOAT = 5.0,                      -- Supply Voltage (Volts)
    @R1 FLOAT = 1000.0,                    -- Resistor 1 (Ohms - Astable only)
    @R2 FLOAT = 10000.0,                   -- Resistor 2 (Ohms - Astable only)
    @C_uF FLOAT = 10.0,                    -- Capacitor (Microfarads - Astable only)
    @TimeStep_ms FLOAT = 1.0,              -- Simulation resolution (Milliseconds)
    @TotalSteps INT = 500,                 -- Number of steps to simulate
    @TriggerEvents_ms VARCHAR(MAX) = '',   -- CSV timestamps for Pin 2 low pulses (Bistable)
    @ResetEvents_ms VARCHAR(MAX) = '',     -- CSV timestamps for Pin 4 low pulses (Bistable)
    @PulseWidth_ms FLOAT = 20.0            -- Duration of button press (Milliseconds)
AS
BEGIN
    SET NOCOUNT ON;

    -- Parse Bistable button press events into table variables
    DECLARE @Triggers TABLE (Start_ms FLOAT);
    DECLARE @Resets TABLE (Start_ms FLOAT);

    IF @Mode = 'BISTABLE'
    BEGIN
        INSERT INTO @Triggers (Start_ms)
        SELECT TRY_CAST(value AS FLOAT) 
        FROM STRING_SPLIT(@TriggerEvents_ms, ',') 
        WHERE TRY_CAST(value AS FLOAT) IS NOT NULL;

        INSERT INTO @Resets (Start_ms)
        SELECT TRY_CAST(value AS FLOAT) 
        FROM STRING_SPLIT(@ResetEvents_ms, ',') 
        WHERE TRY_CAST(value AS FLOAT) IS NOT NULL;
    END

    -- Base SI Conversions & Thresholds
    DECLARE @C FLOAT = @C_uF / 1000000.0;
    DECLARE @dt FLOAT = @TimeStep_ms / 1000.0;
    DECLARE @V_upper FLOAT = (2.0 / 3.0) * @Vcc;
    DECLARE @V_lower FLOAT = (1.0 / 3.0) * @Vcc;

    -- RC Constants (Astable)
    DECLARE @Alpha_Charge FLOAT = 1.0 - EXP(-@dt / ((@R1 + @R2) * @C));
    DECLARE @Alpha_Discharge FLOAT = 1.0 - EXP(-@dt / (@R2 * @C));

    WITH TimerCTE AS (
        -- Anchor Member (t = 0)
        SELECT 
            0 AS StepNum,
            CAST(0.0 AS FLOAT) AS Time_ms,
            CAST(0.0 AS FLOAT) AS V_cap,
            CASE WHEN @Mode = 'ASTABLE' THEN 1 ELSE 0 END AS Q_Out,
            0 AS Discharge_On,
            @Vcc AS Pin2_Trigger_V,
            @Vcc AS Pin4_Reset_V

        UNION ALL

        -- Recursive Member
        SELECT 
            c.StepNum + 1,
            c.Time_ms + @TimeStep_ms,

            -- Capacitor Voltage (Active in Astable, 0V in Bistable)
            CASE 
                WHEN @Mode = 'BISTABLE' THEN 0.0
                WHEN c.Discharge_On = 0 THEN c.V_cap + (@Vcc - c.V_cap) * @Alpha_Charge
                ELSE c.V_cap + (0.0 - c.V_cap) * @Alpha_Discharge
            END AS V_cap,

            -- Output State (Pin 3)
            CASE 
                WHEN @Mode = 'ASTABLE' THEN
                    CASE 
                        WHEN (CASE WHEN c.Discharge_On = 0 THEN c.V_cap + (@Vcc - c.V_cap) * @Alpha_Charge ELSE c.V_cap + (0.0 - c.V_cap) * @Alpha_Discharge END) >= @V_upper THEN 0
                        WHEN (CASE WHEN c.Discharge_On = 0 THEN c.V_cap + (@Vcc - c.V_cap) * @Alpha_Charge ELSE c.V_cap + (0.0 - c.V_cap) * @Alpha_Discharge END) <= @V_lower THEN 1
                        ELSE c.Q_Out
                    END
                ELSE -- BISTABLE LOGIC (Pin 4 Reset overrides Pin 2 Trigger)
                    CASE 
                        WHEN EXISTS (SELECT 1 FROM @Resets r WHERE (c.Time_ms + @TimeStep_ms) BETWEEN r.Start_ms AND (r.Start_ms + @PulseWidth_ms)) THEN 0
                        WHEN EXISTS (SELECT 1 FROM @Triggers t WHERE (c.Time_ms + @TimeStep_ms) BETWEEN t.Start_ms AND (t.Start_ms + @PulseWidth_ms)) THEN 1
                        ELSE c.Q_Out
                    END
            END AS Q_Out,

            -- Discharge Pin (Pin 7)
            CASE 
                WHEN @Mode = 'BISTABLE' THEN 0
                WHEN (CASE WHEN c.Discharge_On = 0 THEN c.V_cap + (@Vcc - c.V_cap) * @Alpha_Charge ELSE c.V_cap + (0.0 - c.V_cap) * @Alpha_Discharge END) >= @V_upper THEN 1
                WHEN (CASE WHEN c.Discharge_On = 0 THEN c.V_cap + (@Vcc - c.V_cap) * @Alpha_Charge ELSE c.V_cap + (0.0 - c.V_cap) * @Alpha_Discharge END) <= @V_lower THEN 0
                ELSE c.Discharge_On
            END AS Discharge_On,

            -- Track Pin 2 Voltage for plotting (Pulled to 0V when pressed)
            CASE 
                WHEN @Mode = 'BISTABLE' AND EXISTS (SELECT 1 FROM @Triggers t WHERE (c.Time_ms + @TimeStep_ms) BETWEEN t.Start_ms AND (t.Start_ms + @PulseWidth_ms)) THEN 0.0
                ELSE @Vcc 
            END AS Pin2_Trigger_V,

            -- Track Pin 4 Voltage for plotting (Pulled to 0V when pressed)
            CASE 
                WHEN @Mode = 'BISTABLE' AND EXISTS (SELECT 1 FROM @Resets r WHERE (c.Time_ms + @TimeStep_ms) BETWEEN r.Start_ms AND (r.Start_ms + @PulseWidth_ms)) THEN 0.0
                ELSE @Vcc 
            END AS Pin4_Reset_V

        FROM TimerCTE c
        WHERE c.StepNum < @TotalSteps
    )
    SELECT 
        StepNum,
        ROUND(Time_ms, 3) AS Time_ms,
        ROUND(V_cap, 4) AS Capacitor_V,
        Q_Out * @Vcc AS Output_V,
        Pin2_Trigger_V,
        Pin4_Reset_V,
        Discharge_On AS Discharge_Pin_Active
    FROM TimerCTE
    OPTION (MAXRECURSION 32767);
END;
GO
