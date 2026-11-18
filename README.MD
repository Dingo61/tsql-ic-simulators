# Classic Integrated Circuits Simulated in T-SQL & Streamlit

A hands-on engineering series exploring how classic analog, digital, and mixed-signal Integrated Circuits (ICs) can be modeled using **SQL Server (T-SQL)** as a discrete-time physics and logic engine, paired with **Python & Streamlit** for interactive oscilloscope visualizations.

A 6-part hands-on engineering series exploring how classic analog, digital, and mixed-signal Integrated Circuits (ICs) can be modeled using **SQL Server (T-SQL)** as a discrete-time physics and logic engine, paired with **Python & Streamlit** for interactive oscilloscope visualizations.


## Why T-SQL for Hardware Simulation?
While SQL is traditionally used for transactional and analytical workloads, its declarative set-based primitives—recursive Common Table Expressions (CTEs), bitwise operators, window functions (`LAG`/`LEAD`), and relational truth tables—map surprisingly well to state machines, RC differential equations, and digital logic gates.

---

## Series Index

| Part | IC Model | Category | Core T-SQL Techniques | Article Link |
| :--- | :--- | :--- | :--- | :--- |
| **01** | **[NE555 Precision Timer](./01-ne555-timer)** | Mixed-Signal Timer | Recursive CTEs, RC exponential decay, SR latch logic | *[Read Part 1](#)* |
| **02** | **[CD4017 Decade Counter](./02-cd4017-decade-counter)** | Sequential Logic | `LAG()` rising-edge detection, modulo arithmetic (`% 10`) | *[Read Part 2](#)* |
| **03** | **[74HC595 Shift Register](./03-74hc595-shift-register)** | Serial-to-Parallel | Bitwise shifting (`&`, `\|`), dual-register state, `NULL` Hi-Z | *[Read Part 3](#)* |
| **04** | **[LM741 Op-Amp](./04-lm741-op-amp)** | Analog | Slew-rate clamping, supply-rail saturation clipping | *[Read Part 4](#)* |
| **05** | **[74LS181 4-Bit ALU](./05-74ls181-4bit-alu)** | Combinational CPU | Set-based `CROSS JOIN` truth matrix, opcode decoding | *[Read Part 5](#)* |
| **06** | **[ADC0804 8-Bit SAR ADC](./06-adc0804-sar-adc)** | Mixed-Signal | Recursive binary search (SAR), `FIRST_VALUE()` sample-and-hold | *[Read Part 6](#)* |

---

## Prerequisites
* **SQL Server:** SQL Server 2016+ (Developer, Express, or Docker container) — *requires `STRING_SPLIT` and recursive CTE support.*
* **ODBC Driver:** [ODBC Driver 17 or 18 for SQL Server](https://microsoft.com)
* **Python:** Python 3.9 or higher

---

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/Dingo61/tsql-ic-simulators.git
cd tsql-ic-simulators
```

### 2. Set Up the Python Environment
```bash
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS / Linux:
source .venv/bin/activate

pip install -r requirements.txt
```

### 3. Configure Database Connection

Create your local `.env` file from the supplied template.

**Windows PowerShell:**
```powershell
Copy-Item .env.example .env
```

**macOS / Linux:**
```bash
cp .env.example .env
```

Then edit `.env` with your SQL Server connection details:
```env
DB_SERVER=localhost
DB_NAME=IC_Simulations
DB_DRIVER=ODBC Driver 17 for SQL Server
DB_TRUSTED_CONNECTION=yes

# Required only when DB_TRUSTED_CONNECTION=no
# DB_USER=
# DB_PASSWORD=
```

The `.env` file is excluded from Git and must not be committed.

### 4. Deploy an IC Stored Procedure & Launch Streamlit
1. Create an empty database in SQL Server (e.g., `CREATE DATABASE IC_Simulations;`).
2. Execute the `schema.sql` script inside the desired IC folder (e.g., `01-ne555-timer/schema.sql`).
3. Run the Streamlit app from the repository root:
```bash
streamlit run 01-ne555-timer/app.py
```

---

## Repository Structure
```text
tsql-ic-simulators/
├── .env.example                      # Environment variable template
├── .gitignore                        # Ignores .env, .venv, and __pycache__
├── README.md                         # Series overview & setup guide
├── requirements.txt                  # Python dependencies
├── shared/
│   ├── __init__.py
│   └── db_connection.py              # Centralized SQL Server connection & query runner
├── 01-ne555-timer/                   # Astable & Bistable RC Timer
├── 02-cd4017-decade-counter/         # Chained 10-Stage Johnson Counter
├── 03-74hc595-shift-register/        # 8-Bit SIPO Shift Register with Hi-Z
├── 04-lm741-op-amp/                  # Analog Op-Amp with Slew-Rate Distortion
├── 05-74ls181-4bit-alu/              # 4-Bit Vintage CPU ALU & 256-State Matrix
└── 06-adc0804-sar-adc/               # 8-Bit Successive Approximation ADC
```

### Launch the Unified Multi-IC Workbench (All 6 Chips)
To explore all six simulated ICs from a single dashboard—complete with automatic SQL Server stored-procedure checks—run:

```bash
streamlit run launcher.py
```


## License
MIT License — feel free to fork, modify, and use these simulations in your own articles or experiments.
