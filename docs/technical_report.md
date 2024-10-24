# DIMPLE Technical Report

DIMPLE (Digital Ising Machines from Programmable Logic, Easily!) is an attempt to create an entirely digital coupled Ising machine. Instead of using voltage-based coupling, this project leverages a phase-based coupling method where different oscillators control configurable delay cells in each others' oscillation path. The aim of the project is to create Ising machine that can be deployed on an FPGA allowing for technological ubiquity, and ultimately manufactured in an advanced process node.

## Top-Level Digital Ising Machine

The following diagram shows the top-level architecture of the computational core of DIMPLE (Digital Ising Machines from Programmable Logic, Easily) implementation without its AXI interface. This design implements a coupled-oscillator system on FPGA to solve optimization problems like Maximum Cut. This implementation achieves microsecond-scale convergence for optimization problems, while being fully digital and deployable on commercial FPGAs like AWS F1 instances.

```mermaid
graph TD
    subgraph INPUTS[Input Ports]
        clk["clk [1]"]
        ising_rstn["ising_rstn [1]"]
        counter_max["counter_max [31:0]"]
        counter_cutoff["counter_cutoff [31:0]"]
        axi_rstn["axi_rstn [1]"]
        wready["wready [1]"]
        wr_addr["wr_addr [31:0]"]
        wdata["wdata [31:0]"]
        rd_addr["rd_addr [31:0]"]
    end

    subgraph CORE["core_matrix"]
        direction LR
        core_logic[".N=3
        .NUM_WEIGHTS=5
        .WIRE_DELAY=20
        .NUM_LUTS=2"]
    end

    subgraph SAMPLER["sample"]
        direction LR
        sample_logic[".N=3"]
    end

    subgraph OUTPUTS[Output Ports]
        phase["phase [31:0]"]
        rdata["rdata [31:0]"]
    end

    %% Core Matrix Connections
    clk -->|"[1]"| CORE
    ising_rstn -->|"[1]"| CORE
    axi_rstn -->|"[1]"| CORE
    wready -->|"[1]"| CORE
    wr_addr -->|"[31:0]"| CORE
    wdata -->|"[31:0]"| CORE
    rd_addr -->|"[31:0]"| CORE
    CORE -->|"[31:0]"| rdata
    CORE -->|"[N-1:0]"| outputs
    
    %% Sampler Connections
    clk -->|"[1]"| SAMPLER
    ising_rstn -->|"[1]"| SAMPLER
    counter_max -->|"[31:0]"| SAMPLER
    counter_cutoff -->|"[31:0]"| SAMPLER
    rd_addr -->|"[31:0]"| SAMPLER
    SAMPLER -->|"[31:0]"| phase

    %% Internal Connection
    CORE =="outputs[2:0] (N-1:0)"==> SAMPLER

    style CORE fill:#e1f5fe,stroke:#0288d1,stroke-width:2px
    style SAMPLER fill:#e8f5e9,stroke:#388e3c,stroke-width:2px
    style INPUTS fill:#fff3e0,stroke:#ff9800,stroke-width:2px
    style OUTPUTS fill:#fce4ec,stroke:#e91e63,stroke-width:2px
```

### Architecture Details
The diagram shows the two main components of DIMPLE:

#### `core_matrix`
Implements an array of coupled ring oscillators, in this case it contains N=3 oscillators in this example (can scale up to 128 in full implementation) and uses digital "resistors" made from LUTs for coupling between oscillators `WIRE_DELAY` and `NUM_LUTS` define the underlying oscillator coupling circuitry which are then programmed using the `wdata` and `wr_data` registers and `w_ready` flag via the AXI interface. `clk`, `axi_rstn` and `ising_rstn` are used to control logic in the `coupled_cells` and `shorted_cells` which the individual oscillators are composed of. All status/control data is then routed to 32-bit address `rd_addr` via the `rdata` line via the AXI interface, where as oscillator data is fed to the `sample` module via the `output[N-1:0]` wire.

#### `sample`
 Compares oscillator phases fed to it on the `output[N-1:0]` wire to determine spin states (+1 or -1) and uses `counter_max`/`counter_cutoff` to determine sampling window. The design outputs final phase measurements through `phase` port. The AXI interface (`wready`, `wr_addr`, `wdata`, `rd_addr`, `rdata`) allows programming of coupling weights between oscillators, effectively defining the optimization problem to be solved.

## Core Matrix

The core computational element of DIMPLE is the `core_matrix` module, which implements an NxN array of coupled ring oscillators. This module creates the physical substrate for solving Ising model problems through oscillator phase relationships. The architecture enables all-to-all coupling between N spins through a digital implementation.

### Structural Overview

The following diagram details the structural implementation of core_matrix, showing the primary data paths and control interfaces:

```mermaid
graph TD
    subgraph CTRL_INPUT[Control Bus]
        style CTRL_INPUT fill:#e6f3ff,stroke:#666
        ising_rstn
        axi_rstn
        w_ready
        clk
    end

    subgraph AXI[AXI Bus]
        style AXI fill:#fff0f0,stroke:#666
        wr_addr["wr_addr[31:0]"]
        rd_addr["rd_addr[31:0]"]
        wdata["wdata[31:0]"]
        rdata["rdata[31:0]"]
    end
    
    subgraph CONTROL_LOGIC[Control Logic]
        style CONTROL_LOGIC fill:#f0fff0,stroke:#666
        direction LR
        w_addr_mask["WEIGHT_ADDR_MASK"]
        wr_match["wr_match[7:0] (==)"]
        set_addr{"wready HIGH?
        Yes, use wr_addr
        No, use rd_addr"}
        s_addr["s_addr[15:0]"]
        d_addr["d_addr[15:0]"]
    end

    subgraph COLS[Column Array]
        style COLS fill:#fff6e6,stroke:#666
        direction LR
        colss["N Columns<br/>K=0,1,2,..."]

        col_idec[Column i-1]
        col_ienc[Column i+1]

        subgraph COL_I[Column i]
            style COL_I fill:#ffebcc,stroke:#666
            s_exp["s_exp[15:0]"]
            coupled_col["coupled_col Module
            .N(N),
		    .K(i-1),
			.NUM_WEIGHTS(NUM_WEIGHTS),
			.WIRE_DELAY(WIRE_DELAY),
			.NUM_LUTS(NUM_LUTS)"]
            s_match["=="]
            wr_match_col["wr_match_col (&)"]
            r_data_out["rdata_out[31:0]"]
            r_data_col["rdata_col[31:0]"]

            ternary["wr_match_col ? rdata_col : rdata_out"]
        end
        column_out["column_out[N-1:0]"]
    end

    subgraph SHORTS[Shorted Cells]
        style SHORTS fill:#f0f0ff,stroke:#666
        direction LR
        wr_match_sh["wr_match & (s_addr == d_addr) & (s_addr == i)"]
        subgraph SHORTI[Shorted Cell i]
            style SHORTI fill:#e6e6ff,stroke:#666
            direction LR
        end
    end

    subgraph BUFS[Buffer Chains]
        style BUFS fill:#fff0ff,stroke:#666
        direction LR
        buf_in["Buffer Inputs"]
        buf_logic["WIRE_DELAY Chains"]
        buf_out["Buffer Outputs"]
    end

    subgraph OUT
        outputs
    end

    %% I/O Logic
    wr_addr -->|"[31:24]"| wr_match
    w_addr_mask --> wr_match
    w_ready --> set_addr
    wr_addr -->|"[23:2]"| set_addr
    rd_addr -->|"[23:2]"| set_addr
    set_addr -->|"{5'b0,addr[12:2]}"| s_addr
    set_addr -->|"{5'b0,addr[23:13]}"| d_addr
    

    %% Column Logic
    d_addr -->|"add i mod N"| s_exp
    s_exp --> s_match
    s_addr --> s_match
    s_match --> wr_match_col
    wr_match --> wr_match_col
    col_idec --> coupled_col
    coupled_col --> col_ienc
    col_ienc -.-> col_idec
    CTRL_INPUT ==> coupled_col
    wr_match --> coupled_col
    s_addr --> coupled_col
    d_addr --> coupled_col
    wdata --> coupled_col
    coupled_col -->|"[i]"|column_out
    coupled_col --> r_data_col
    r_data_col --> ternary
    r_data_out --> ternary
    wr_match_col --> ternary
    ternary --> rdata

    %% Shorted Cell Logic
    column_out -->|"osc_in[i]"| SHORTI
    CTRL_INPUT ==> SHORTI
    wdata --> SHORTI
    wr_match_sh --> SHORTI
    wr_match --> wr_match_sh
    s_addr --> wr_match_sh
    d_addr --> wr_match_sh
    SHORTI -->|"osc_out"| BUFS
    BUFS -->|"osc_del[i]"| COL_I

    column_out --> outputs
```

### Implementation Details
The core_matrix module is parameterized by four key values:

`N`: Number of oscillators/spins in the system
`NUM_WEIGHTS`: Weight resolution for coupling strengths
`WIRE_DELAY`: Number of delay stages in feedback path
`NUM_LUTS`: Number of LUTs per delay element

The architecture consists of five main functional blocks:

**Address Decoder**: Processes AXI memory-mapped interface addresses, splitting them into source (`s_addr`) and destination (`d_addr`) fields for weight configuration. The upper address bits are validated against `WEIGHT_ADDR_MASK` to ensure proper addressing.
**Column Array**: Implements `N` columns of coupled cells, where each column `k` introduces couplings with distance `k`. Column `0` serves as the input stage, while columns `1` through `N-1` contain programmable coupling cells that implement the Ising interaction weights.
**Shorted Cells**: Provides initialization and measurement points for each ring oscillator. These cells can be programmed through the AXI interface to set initial oscillator states and read current states.
**Delay Buffer Arrays**: Creates the primary oscillator feedback path using cascaded LUT-based buffers. The `WIRE_DELAY` parameter controls the oscillation frequency by setting the total path delay.
**Feedback Path**: Connects the delay buffer outputs back to Column 0, completing N independent ring oscillator loops that can influence each other through the coupling columns.

All synchronous interfaces (AXI) are clocked by the system clock, while the oscillator array operates asynchronously to maximize operating frequency. The outputs bus provides direct access to oscillator states for phase measurement and analysis.


## Coupled Column (`coupled_col`)
The coupled column implements N oscillator couplings with a fixed distance pattern K. For each input i, it creates 
a coupling to position (i+K+1)%N, forming an asymmetric coupling pattern around the ring.

```mermaid
graph TD

    subgraph CTRL[Control Flags]
        style CTRL fill:#e6f3ff,stroke:#666
        ising_rstn
        clk
        axi_rstn
        wready
    end

    subgraph AXI[AXI Bus]
        style AXI fill:#fff0f0,stroke:#666
        wr_match
        s_addr
        d_addr
        wdata
        rdata
    end

    subgraph OSC[Oscillator Wires]
        style OSC fill:#f0fff0,stroke:#666
        in_wires["in_wires[j]"]
        out_wires["out_wires[j]"]
    end

    subgraph COUPLING[Coupling Formula]
        style COUPLING fill:#ffe6ff,stroke:#666
        formula["out_wires[(j+K)%N] → in_wires[j]"]
    end

    subgraph CELLS[Coupled Cells]
        style CELLS fill:#fff6e6,stroke:#666
        subgraph CELL_J[Coupled Cell j]
            match_loop["wr_match & (d_addr == j)"]
            logic["NUM_WEIGHTS<br/>NUM_LUTS"]
            rdata_out["wr_match_loop ? rdata_loop : coupled_loop[j-1].rdata_out"]
        end
        rdata_loop
    end

    subgraph BUFS[Buffer Chains]
        style BUFS fill:#f0f0ff,stroke:#666
        buflogic["WIRE_DELAY<br/>NUM_LUTS"]
    end

    %% Logic
    wr_match --> match_loop
    d_addr --> match_loop
    wdata --> CELLS
    in_wires --> CELLS
    CTRL ==> CELLS
    rdata_out --> rdata_loop
    rdata_loop --> rdata
    CELLS ==> BUFS
    BUFS ==> out_wires
    out_wires --> COUPLING
    COUPLING --> in_wires
```

### Key Parameters
- `N`: Number of oscillators (typically 3-64)
- `K`: Coupling distance (0 to N-1)
- `NUM_WEIGHTS`: Resolution of coupling strength
- `WIRE_DELAY`: Stabilizing delay length
- `NUM_LUTS`: LUTs per delay element

### Architecture
1. **Coupling Array**: N coupled_cells arranged to implement K+1 coupling pattern:
    - Input i couples to output (i+K+1)%N
    - Each cell has independent weight configuration
    - Forms asymmetric coupling matrix

2. **Delay Stabilization**: Each output passes through `WIRE_DELAY` buffers:
  ```verilog
  wire [WIRE_DELAY-1:0] out_del;
  buffer #(NUM_LUTS) buf0(.in(out_wires_pre[j]), .out(out_del[0]));
  ```

3. **Configuration**: AXI interface for weight programming:
    - `wr_match` selects column
    - `d_addr` selects specific cell
    - `wdata` sets coupling weight

### Coupled Cell (coupled_cell)
Each coupled cell implements a programmable delay element that modifies signal timing based on phase relationships.
Key Parameters

`NUM_WEIGHTS`: Number of possible delay values (coupling strengths)
`NUM_LUTS`: LUTs per basic delay element

```mermaid
graph TD
    subgraph INPUTS[Input Ports]
        style INPUTS fill:#e6f3ff,stroke:#666
        ising_rstn
        sout
        din
        clk
        axi_rstn
        wready
        wr_addr_match["wr_addr_match"]
        wdata["wdata[31:0]"]
    end

    subgraph WEIGHT_LOGIC[Weight Storage]
        style WEIGHT_LOGIC fill:#fff0f0,stroke:#666
        weight_reg["weight register"]
        weight_nxt["weight_nxt = 
        wready & wr_addr_match ? 
        wdata : weight"]
        weight_oh["weight one-hot decoder
        weight_oh[i] = (weight == i)"]
    end

    subgraph DELAY_CHAIN[Delay Buffer Chain]
        style DELAY_CHAIN fill:#f0fff0,stroke:#666
        d_buf0["d_buf[0]
        buffer(NUM_LUTS)"]
        d_buf1["d_buf[1]
        buffer(NUM_LUTS)"]
        d_bufn["d_buf[NUM_WEIGHTS-1]
        buffer(NUM_LUTS)"]
    end

    subgraph MISMATCH[Mismatch Logic]
        style MISMATCH fill:#fff6e6,stroke:#666
        mismatch_d["mismatch_d = sout ^ din"]
        d_sel_ma["d_sel_ma[i] = 
        weight_oh[NUM_WEIGHTS-1-i] & d_buf[i]"]
        d_sel_mi["d_sel_mi[i] = 
        weight_oh[i] & d_buf[i]"]
        d_ma["d_ma = |d_sel_ma"]
        d_mi["d_mi = |d_sel_mi"]
    end

    subgraph OUTPUT_LOGIC[Output Stage]
        style OUTPUT_LOGIC fill:#f0f0ff,stroke:#666
        dout_pre["dout_pre = 
        mismatch_d ? d_mi : d_ma"]
        dout_no_glitch["dout_no_glitch = 
        (dout == din) ? dout : dout_pre"]
        dout_int["dout_int
        buffer(NUM_LUTS)"]
        dout_rst["dout_rst
        LDCE/conditional"]
        dout["dout = 
        ising_rstn ? dout_rst : din"]
    end

    %% Connections
    din --> d_buf0
    d_buf0 --> d_buf1
    d_buf1 --> d_bufn
    din --> mismatch_d
    sout --> mismatch_d
    weight_reg --> weight_oh
    weight_oh --> d_sel_ma
    weight_oh --> d_sel_mi
    d_buf0 --> d_sel_ma
    d_buf0 --> d_sel_mi
    d_sel_ma --> d_ma
    d_sel_mi --> d_mi
    d_ma --> dout_pre
    d_mi --> dout_pre
    mismatch_d --> dout_pre
    dout_pre --> dout_no_glitch
    din --> dout_no_glitch
    dout_no_glitch --> dout_int
    dout_int --> dout_rst
    dout_rst --> dout
    ising_rstn --> dout
    din --> dout

    %% Weight update path
    wdata --> weight_nxt
    wready --> weight_nxt
    wr_addr_match --> weight_nxt
    weight_nxt --> weight_reg
    axi_rstn --> weight_reg
    clk --> weight_reg
```

#### Weight Configuration
```verilog
reg  [$clog2(NUM_WEIGHTS)-1:0] weight;
wire [NUM_WEIGHTS-1:0] weight_oh;
```

Stores coupling strength in weight register (0 to `NUM_WEIGHTS-1`) and then converts it to a one-hot encoding for delay selection. Configurable through AXI interface (`wready`/`wr_addr_match`/`wdata`) but defaults to middle weight on reset (`NUM_WEIGHTS/2`).

#### Phase-Based Delay Selection

Note that the `din` and `sout` lines are the `in_wires` and `out_wires` seen in the `coupled_col` diagram above.

```verilog
assign mismatch_d = sout ^ din;
wire [NUM_WEIGHTS-1:0] d_buf;  // Delay buffer chain
```

The cell implements asymmetric coupling through two key mechanisms:

**For In-Phase Oscillators** (`mismatch_d = 0`):

Uses `d_sel_ma` (match) delays where, stronger weights = longer delays = weaker coupling, this is implemented by indexing from end of `weight_oh: weight_oh[NUM_WEIGHTS-1-i]`.

**For Out-of-Phase Oscillators** (`mismatch_d = 1`):

Uses `d_sel_mi` (mismatch) delays where stronger weights = shorter delays = stronger coupling, this is implemented by direct indexing: `weight_oh[i]`



#### Delay Implementation
```verilog
generate for (i = 1; i < NUM_WEIGHTS; i = i + 1) begin
    buffer #(NUM_LUTS) bufid(.in(d_buf[i-1]), .out(d_buf[i]));
end endgenerate
```

Chain of `NUM_WEIGHTS` delay elements where each element uses `NUM_LUTS` Look-Up Tables (LUTs) which are configured as inverters (`INIT=2'b10`), `dont_touch` prevents optimization.

#### Glitch Prevention
```verilog
assign dout_no_glitch = (dout == din) ? dout : dout_pre;
LDCE d_latch (.Q(dout_rst), .D(dout_int), .G(ising_rstn));
```

Three layers of stability protection:

1. Glitch suppression logic prevents spurious transitions
2. Feedback stabilization buffer
3. Transparent latch masks combinational loops from tools

#### Physical Operation
The cell modifies oscillator coupling strength by adjusting signal propagation delays:

**Strong Positive Coupling**:

- Short delay when oscillators mismatched
- Long delay when matched
- Brings oscillators into phase


**Strong Negative Coupling**:

- Long delay when oscillators mismatched
- Short delay when matched
- Pushes oscillators out of phase


**Zero Coupling** (`weight = NUM_WEIGHTS/2`):

- Equal delays for match/mismatch
- No phase influence

All delays are implemented through cascaded LUTs to ensure predictable timing characteristics across FPGA implementations. This creates controlled, predictable delay chains that implement the coupling interaction between oscillators.

### Shorted Cell

```mermaid
graph TD
    subgraph INPUTS[Input Ports]
        style INPUTS fill:#e6f3ff,stroke:#666
        ising_rstn
        sin[sin]
        clk
        axi_rstn
        wready
        wr_addr_match
        wdata["wdata[31:0]"]
    end

    subgraph SPIN_LOGIC[Spin Register]
        style SPIN_LOGIC fill:#fff0f0,stroke:#666
        spin["spin reg"]
        spin_nxt["spin_nxt = 
        wready & wr_addr_match ? 
        wdata[0] : spin"]
    end

    subgraph OUTPUT_PATH[Output Path]
        style OUTPUT_PATH fill:#f0fff0,stroke:#666
        out["out = 
        ising_rstn ? s_int : spin"]
        dbuf["buffer #(NUM_LUTS)
        in: ~out"]
        dout
    end

    subgraph LATCH_LOGIC[Latch Logic]
        style LATCH_LOGIC fill:#fff6e6,stroke:#666
        subgraph SIM[Simulation]
            s_int_sim["s_int = 
            ising_rstn ? sin : 1'b0"]
        end
        subgraph IMPL[Implementation]
            s_int_impl["LDCE s_latch
            D: sin
            G: ising_rstn
            dont_touch"]
        end
    end

    %% Control paths
    wready --> spin_nxt
    wr_addr_match --> spin_nxt
    wdata --> spin_nxt
    spin_nxt --> spin
    axi_rstn ==> SPIN_LOGIC
    clk ==> SPIN_LOGIC

    %% Output generation
    spin --> out
    ising_rstn --> out
    s_int_sim --> out
    s_int_impl --> out
    out --> dbuf
    dbuf --> dout

    %% Latch paths
    sin --> s_int_sim
    sin --> s_int_impl
    ising_rstn --> s_int_sim
    ising_rstn --> s_int_impl

    %% Read data
    spin --> rdata[rdata]
    spin --> spin_nxt
```

The `shorted_cell` module initializes and maintains spin states. It acts as an initialization point for each oscillator in the system, allowing programmatic control over the spin's starting state (+1 or -1) while maintaining proper oscillation during normal operation.

### Key Functions

#### 1. Spin State Management
- Stores and maintains a programmable spin state in a register
- Allows AXI bus writes to modify the spin value through `wdata[0]`
- State is readable through the `rdata` output for monitoring

#### 2. Oscillator Phase Control
The module serves two distinct operational modes:

##### Initialization Mode (`ising_rstn` low)
- Forces the output `dout` to match the programmed spin state
- Effectively initializes the oscillator to a known +1 or -1 state

##### Running Mode (`ising_rstn` high)
- Allows normal oscillation by passing through the input signal `sin`
- Uses either simulation logic or an LDCE (transparent latch) to prevent combinational loops
- Inverts the output through a buffer chain to maintain oscillation

#### 3. Delay Management
- Implements configurable delay through `NUM_LUTS` parameter
- Uses buffer chains to ensure proper oscillator timing
- Helps maintain stable oscillation frequency

### Context in DIMPLE Architecture
The shorted cell is used to:
1. Initialize the Ising machine spins to specific states before solving
2. Maintain stable oscillation during problem-solving
3. Provide clean phase transitions between initialization and running modes
4. Enable readback of spin states through the AXI interface

The module's combination of programmable initialization and controlled oscillation makes it essential for setting up and solving Ising optimization problems in DIMPLE's FPGA implementation.

### Implementation Notes
- Uses transparent latches (`LDCE`) in hardware to trick synthesis tools about combinational loops
- Implements different behavior for simulation vs hardware through `ifdef` directives
- Part of DIMPLE's all-digital approach to oscillator-based computing

## Buffer

```mermaid
graph TD
    subgraph PORTS[Buffer Interface]
        style PORTS fill:#e6f3ff,stroke:#666
        in
        out
    end

    subgraph SIM[Simulation]
        style SIM fill:#fff0f0,stroke:#666
        o_reg["o_reg #1 delay"]
    end

    subgraph IMPL[Implementation]
        style IMPL fill:#f0fff0,stroke:#666
        lut0["buf_lut_0 (LUT1)"]
        lut1["buf_lut_1 (LUT1)"]
        lutN["buf_lut_N (LUT1)"]
    end

    %% Simulation path
    in --> o_reg
    o_reg --> out

    %% Implementation path
    in --> lut0
    lut0 --> lut1
    lut1 --> lutN
    lutN --> out
```

## Phase Sampling and Measurement Block

### Sample Module Overview
The sample module performs phase measurement across N oscillators, using synchronization and counter-based techniques to determine the relative phases of the oscillators in the system.

#### Key Parameters
- `N`: Number of oscillators to sample (typically matches `core_matrix` N)
- `counter_max`: Maximum value for phase counters
- `counter_cutoff`: Initial/reset value for counters

### Architecture

```mermaid
graph TD
    subgraph INPUTS[Input Ports]
        style INPUTS fill:#e6f3ff,stroke:#666
        clk
        rstn
        counter_max["counter_max[31:0]"]
        counter_cutoff["counter_cutoff[31:0]"]
        outputs["outputs[N-1:0]"]
        rd_addr["rd_addr[31:0]"]
    end

    subgraph SYNC[Phase Synchronizer]
        style SYNC fill:#fff0f0,stroke:#666
        mismatch0["phase_mismatch_0 = 
        outputs ^ {N{outputs[N-1]}}"]
        mismatch1["phase_mismatch_1"]
        mismatch2["phase_mismatch_2"]
        mismatch3["phase_mismatch_3"]
    end

    subgraph COUNTER_LOGIC[Counter Control]
        style COUNTER_LOGIC fill:#f0fff0,stroke:#666
        rst_detect["rst_start = rstn & ~rstn_old"]
        overflow["overflow[i] = 
        phase_counters[i] >= counter_max"]
        underflow["underflow[i] = 
        phase_counters[i] == 0"]
    end

    subgraph PHASE_COUNT[Phase Counter Array]
        style PHASE_COUNT fill:#fff6e6,stroke:#666
        counter_array["phase_counters[N-1:0][31:0]"]
        counter_next["phase_counters_nxt[i] =
        rst_start ? counter_cutoff :
        ~rstn ? phase_counters[i] :
        phase_mismatch_3[i] ? 
            (underflow[i] ? same : dec) :
            (overflow[i] ? same : inc)"]
    end

    subgraph OUTPUT[Output Selection]
        style OUTPUT fill:#f0f0ff,stroke:#666
        phase_idx["phase_index = 
        (rd_addr - PHASE_ADDR_BASE) >> 2"]
        phase_out["phase[31:0] = 
        phase_counters[phase_index]"]
    end

    %% Synchronizer chain
    outputs --> mismatch0
    mismatch0 --> mismatch1
    mismatch1 --> mismatch2
    mismatch2 --> mismatch3

    %% Counter control
    rstn --> rst_detect
    counter_max --> overflow
    counter_array --> overflow
    counter_array --> underflow

    %% Counter update
    rst_detect --> counter_next
    rstn --> counter_next
    mismatch3 --> counter_next
    overflow --> counter_next
    underflow --> counter_next
    counter_next --> counter_array
    clk --> counter_array

    %% Output path
    rd_addr --> phase_idx
    phase_idx --> phase_out
    counter_array --> phase_out
```

1. **Phase Mismatch Detection**
  - Compares each oscillator phase with reference (last oscillator)
  - Uses XOR operation for phase comparison:
  ```verilog
  assign phase_mismatch_0 = outputs ^ {N{outputs[N-1]}};
  ```

2. **Synchronization Chain**

- 4-stage synchronizer prevents metastability
- Samples asynchronous oscillator outputs into clock domain

```verilog
always @(posedge clk) begin
    phase_mismatch_1 <= phase_mismatch_0;
    phase_mismatch_2 <= phase_mismatch_1;
    phase_mismatch_3 <= phase_mismatch_2;
end
```

3. **Phase Counter Array**

- N 32-bit counters track relative phase relationships
- Increment/decrement based on synchronized phase mismatch
- Bounded by counter_max and zero
- Reset to `counter_cutoff` value on rstn rising edge

4. **Counter Update Logic**

```verilog
assign phase_counters_nxt[i] = 
    rst_start           ? counter_cutoff         :  
    ~rstn              ? phase_counters[i]      :	
    phase_mismatch_3[i] ? (
        underflow[i]   ? phase_counters[i]      :
                        phase_counters[i] - 1 ) :
    (overflow[i]       ? phase_counters[i]      :
                        phase_counters[i] + 1 );
```

#### Output Interface

Phase values readable through memory-mapped interface `rd_addr` selects which oscillator's phase to read. Phase value represents accumulated count of phase relationship.

## AXI Interface and Control Registers

The `ising_axi` module provides an AXI-lite compatible interface for controlling and monitoring the DIMPLE Ising machine.

```mermaid
graph TD
    subgraph AXI_INPUTS[AXI Interface]
        style AXI_INPUTS fill:#e6f3ff,stroke:#666
        clk
        axi_rstn
        subgraph READ_PORT[Read Port]
            arvalid_q
            araddr_q["araddr_q[31:0]"]
            rready
        end
        subgraph WRITE_PORT[Write Port]
            wready
            wr_addr["wr_addr[31:0]"]
            wdata["wdata[31:0]"]
        end
    end

    subgraph ADDR_DECODE[Address Decode]
        style ADDR_DECODE fill:#fff0f0,stroke:#666
        phase_sel["phase_sel = 
        araddr_q[31:12] == PHASE_MASK"]
        weight_sel["weight_sel = 
        araddr_q[31:24] == WEIGHT_MASK"]
        cutoff_sel["wr_addr == CTR_CUTOFF_ADDR"]
        max_sel["wr_addr == CTR_MAX_ADDR"]
        start_sel["wr_addr == START_ADDR"]
    end

    subgraph CONTROL_REGS[Control Registers]
        style CONTROL_REGS fill:#f0fff0,stroke:#666
        counter_cutoff["counter_cutoff[31:0]"]
        counter_max["counter_max[31:0]"]
        ising_rstn_cnt["ising_rstn_cnt[31:0]"]
        ising_rstn["ising_rstn = ising_rstn_cnt > 0"]
    end

    subgraph TOP_ISING[Ising Machine]
        style TOP_ISING fill:#fff6e6,stroke:#666
        u_top_ising["top_ising
        Parameters:
        N, NUM_WEIGHTS,
        WIRE_DELAY, NUM_LUTS"]
        phase_read_val["phase_read_val[31:0]"]
        weight_read_val["weight_read_val[31:0]"]
    end

    subgraph READ_LOGIC[AXI Read Logic]
        style READ_LOGIC fill:#f0f0ff,stroke:#666
        rvalid
        rresp
        rdata["rdata[31:0]"]
    end

    %% Major Control Paths
    clk ==> CONTROL_REGS
    clk ==> READ_LOGIC
    axi_rstn ==> CONTROL_REGS
    axi_rstn ==> READ_LOGIC
    WRITE_PORT ==> CONTROL_REGS
    AXI_INPUTS ==> TOP_ISING
    CONTROL_REGS ==> TOP_ISING

    %% Address Decode
    araddr_q --> phase_sel
    araddr_q --> weight_sel
    wr_addr --> cutoff_sel
    wr_addr --> max_sel
    wr_addr --> start_sel

    %% Read Data Path
    TOP_ISING ==> READ_LOGIC
    ADDR_DECODE ==> READ_LOGIC
    READ_PORT ==> READ_LOGIC
```

### Memory Map

#### Control Registers

1. **Counter Cutoff** (`CTR_CUTOFF_ADDR`)
- Initial/reset value for phase counters
- Write-only Register

2. **Counter Max** (`CTR_MAX_ADDR`)
  - Maximum value for phase counters
  - Write-only register

3. **Reset Control** (`START_ADDR`)
  - Controls ising_rstn signal
  - Write triggers countdown timer
  - Active high during countdown

#### Read Address Space
- **Phase Values** (`PHASE_ADDR_MASK`)
 - Upper bits [31:12] select phase reading
 - Returns current phase counter values

- **Weight Values** (`WEIGHT_ADDR_MASK`)
 - Upper bits [31:24] select weight reading
 - Returns coupling weights

### AXI Protocol Implementation

#### Read Channel
```verilog
always @(posedge clk) begin
   if (arvalid_q) begin
       rvalid <= 1;
       rdata  <= phase_sel  ? phase_read_val  : 
                 weight_sel ? weight_read_val :
                             32'hAAAAAAAA    ;
       rresp  <= 0;
   end
end
```

#### Write Channel

- Direct writes to control registers
- Address-decoded writes to coupling weights
- Reset control with countdown:

```verilog
wire ising_rstn = (ising_rstn_cnt > 0);
```

#### Interface Features

- AXI-lite compatible read/write
- Address-based multiplexing of data sources
- Automatic reset countdown timer
- Default values (0xAAAAAAAA) for unmapped addresses