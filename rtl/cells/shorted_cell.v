`timescale 1ns/1ps

`include "defines.vh"

`ifdef SIM
   `include "buffer.v"
`endif

module shorted_cell #(parameter NUM_LUTS = 2) (
   input  wire ising_rstn,
   input  wire sin,
   output wire dout,
   
   // Synchronous AXI interface
   input  wire        clk,
   input  wire        axi_rstn,
   input  wire        wready,
   input  wire        wr_addr_match, 
   input  wire [31:0] wdata,
   output wire [31:0] rdata
);

   // Counter and wavefront registers
   reg [31:16] cycle_count;
   reg [15:0]  wavefront_count;
   wire        deploy_wavefront;

   // Basic buffer operation 
   wire s_int;
   wire out;
   wire buffer_out;

   assign out = ising_rstn ? s_int : spin;
   buffer #(NUM_LUTS) dbuf(.in(~out), .out(buffer_out));
   assign dout = deploy_wavefront ? sin : buffer_out;

   // Cycle counter
   always @(posedge clk) begin
       if (!axi_rstn) begin
           cycle_count <= 16'b0;
       end else begin
           cycle_count <= cycle_count + 1'b1;
       end
   end

   // Wavefront deployment logic
   assign deploy_wavefront = (cycle_count == wdata[31:16]);
   
   always @(posedge clk) begin
       if (!axi_rstn) begin
           wavefront_count <= 16'b0;
       end else if (deploy_wavefront && (wavefront_count < wdata[15:0])) begin
           wavefront_count <= wavefront_count + 1'b1;
           cycle_count <= 16'b0;
       end
   end

   // Status reporting
   assign rdata = {cycle_count, wavefront_count};

   // Latch logic
   `ifdef SIM
       assign s_int = ising_rstn ? sin : 1'b0;
   `else
       (* dont_touch = "yes" *) LDCE s_latch (.Q(s_int), .D(sin), .G(ising_rstn), .GE(1'b1), .CLR(1'b0));
   `endif

endmodule