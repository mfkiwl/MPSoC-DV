import dii_package::dii_flit;
import opensocdebug::mor1kx_trace_exec;
import optimsoc_config::*;

module riscv_tile #(
  parameter config_t CONFIG = 'x,

  parameter ID       = 'x,
  parameter COREBASE = 'x,

  parameter DEBUG_BASEID = 'x,

  parameter MEM_FILE = 'x,

  localparam CHANNELS   = CONFIG.NOC_CHANNELS,
  localparam FLIT_WIDTH = CONFIG.NOC_FLIT_WIDTH
)
  (
    input                                 dii_flit [1:0] debug_ring_in,
    output                                dii_flit [1:0] debug_ring_out,

    output [ 1:0]                         debug_ring_in_ready,
    input  [ 1:0]                         debug_ring_out_ready,

    output                                ahb3_ext_hsel_o,
    output [PLEN-1:0]                     ahb3_ext_haddr_o,
    output [XLEN-1:0]                     ahb3_ext_hwdata_o,
    input  [XLEN-1:0]                     ahb3_ext_hrdata_i,
    output                                ahb3_ext_hwrite_o,
    output [     2:0]                     ahb3_ext_hsize_o,
    output [     2:0]                     ahb3_ext_hburst_o,
    output [     3:0]                     ahb3_ext_hprot_o,
    output [     1:0]                     ahb3_ext_htrans_o,
    output                                ahb3_ext_hmastlock_o,
    input                                 ahb3_ext_hready_i,
    input                                 ahb3_ext_hresp_i,

    input                                 clk,
    input                                 rst_dbg,
    input                                 rst_cpu,
    input                                 rst_sys,

    input  [CHANNELS-1:0][FLIT_WIDTH-1:0] noc_in_flit,
    input  [CHANNELS-1:0]                 noc_in_last,
    input  [CHANNELS-1:0]                 noc_in_valid,
    output [CHANNELS-1:0]                 noc_in_ready,
    output [CHANNELS-1:0][FLIT_WIDTH-1:0] noc_out_flit,
    output [CHANNELS-1:0]                 noc_out_last,
    output [CHANNELS-1:0]                 noc_out_valid,
    input  [CHANNELS-1:0]                 noc_out_ready
  );

  import optimsoc_functions::*;

  localparam NR_MASTERS = CONFIG.CORES_PER_TILE * 2 + 1;
  localparam NR_SLAVES  = 5;
  localparam SLAVE_DM   = 0;
  localparam SLAVE_PGAS = 1;
  localparam SLAVE_NA   = 2;
  localparam SLAVE_BOOT = 3;
  localparam SLAVE_UART = 4;

  mor1kx_trace_exec [CONFIG.CORES_PER_TILE-1:0] trace;

  logic            ahb3_mem_hsel_o;
  logic [PLEN-1:0] ahb3_mem_haddr_o;
  logic [XLEN-1:0] ahb3_mem_hwdata_o;
  logic [XLEN-1:0] ahb3_mem_hrdata_i;
  logic            ahb3_mem_hwrite_o;
  logic [     2:0] ahb3_mem_hsize_o;
  logic [     2:0] ahb3_mem_hburst_o;
  logic [     3:0] ahb3_mem_hprot_o;
  logic [     1:0] ahb3_mem_htrans_o;
  logic            ahb3_mem_hmastlock_o;
  logic            ahb3_mem_hready_i;
  logic            ahb3_mem_hresp_i;

  // create DI ring segment with routers
  localparam DEBUG_MODS_PER_TILE_NONZERO = (CONFIG.DEBUG_MODS_PER_TILE == 0) ? 1 : CONFIG.DEBUG_MODS_PER_TILE;

  dii_flit [DEBUG_MODS_PER_TILE_NONZERO-1:0] dii_in;
  dii_flit [DEBUG_MODS_PER_TILE_NONZERO-1:0] dii_out;

  logic [DEBUG_MODS_PER_TILE_NONZERO-1:0] dii_in_ready;
  logic [DEBUG_MODS_PER_TILE_NONZERO-1:0] dii_out_ready;

  generate
    if (CONFIG.USE_DEBUG == 1) begin : gen_debug_ring
      genvar i;
      logic [CONFIG.DEBUG_MODS_PER_TILE-1:0][15:0] id_map;
      for (i = 0; i < CONFIG.DEBUG_MODS_PER_TILE; i = i+1) begin
        assign id_map[i][15:0] = 16'(DEBUG_BASEID+i);
      end

      debug_ring_expand #(
        .BUFFER_SIZE (CONFIG.DEBUG_ROUTER_BUFFER_SIZE),
        .PORTS       (CONFIG.DEBUG_MODS_PER_TILE)
      )
      u_debug_ring_segment (
        .clk           (clk),
        .rst           (rst_dbg),
        .id_map        (id_map),
        .dii_in        (dii_in),
        .dii_in_ready  (dii_in_ready),
        .dii_out       (dii_out),
        .dii_out_ready (dii_out_ready),
        .ext_in        (debug_ring_in),
        .ext_in_ready  (debug_ring_in_ready),
        .ext_out       (debug_ring_out),
        .ext_out_ready (debug_ring_out_ready)
      );
    end
  endgenerate

  wire            busms_hsel_o      [0:NR_MASTERS-1];
  wire [PLEN-1:0] busms_haddr_o     [0:NR_MASTERS-1];
  wire [XLEN-1:0] busms_hwdata_o    [0:NR_MASTERS-1];
  wire [XLEN-1:0] busms_hrdata_i    [0:NR_MASTERS-1];
  wire            busms_hwrite_o    [0:NR_MASTERS-1];
  wire [     2:0] busms_hsize_o     [0:NR_MASTERS-1];
  wire [     2:0] busms_hburst_o    [0:NR_MASTERS-1];
  wire [     3:0] busms_hprot_o     [0:NR_MASTERS-1];
  wire [     1:0] busms_htrans_o    [0:NR_MASTERS-1];
  wire            busms_hmastlock_o [0:NR_MASTERS-1];
  wire            busms_hready_i    [0:NR_MASTERS-1];
  wire            busms_hresp_i     [0:NR_MASTERS-1];

  wire            bussl_hsel_o      [0:NR_SLAVES-1];
  wire [PLEN-1:0] bussl_haddr_o     [0:NR_SLAVES-1];
  wire [XLEN-1:0] bussl_hwdata_o    [0:NR_SLAVES-1];
  wire [XLEN-1:0] bussl_hrdata_i    [0:NR_SLAVES-1];
  wire            bussl_hwrite_o    [0:NR_SLAVES-1];
  wire [     2:0] bussl_hsize_o     [0:NR_SLAVES-1];
  wire [     2:0] bussl_hburst_o    [0:NR_SLAVES-1];
  wire [     3:0] bussl_hprot_o     [0:NR_SLAVES-1];
  wire [     1:0] bussl_htrans_o    [0:NR_SLAVES-1];
  wire            bussl_hmastlock_o [0:NR_SLAVES-1];
  wire            bussl_hready_i    [0:NR_SLAVES-1];
  wire            bussl_hresp_i     [0:NR_SLAVES-1];

  wire          snoop_enable;
  wire [31:0]   snoop_adr;

  wire [31:0]   pic_ints_i [0:CONFIG.CORES_PER_TILE-1];

  assign pic_ints_i [0][31:5] = 27'h0;
  assign pic_ints_i [0][ 1:0] = 2'b00;

  genvar c,m,s;

  wire [NR_MASTERS-1:0]           busms_hsel_o_flat;
  wire [NR_MASTERS-1:0][PLEN-1:0] busms_haddr_o_flat;
  wire [NR_MASTERS-1:0][XLEN-1:0] busms_hwdata_o_flat;
  wire [NR_MASTERS-1:0][XLEN-1:0] busms_hrdata_i_flat;
  wire [NR_MASTERS-1:0]           busms_hwrite_o_flat;
  wire [NR_MASTERS-1:0][     2:0] busms_hsize_o_flat;
  wire [NR_MASTERS-1:0][     2:0] busms_hburst_o_flat;
  wire [NR_MASTERS-1:0][     3:0] busms_hprot_o_flat;
  wire [NR_MASTERS-1:0][     1:0] busms_htrans_o_flat;
  wire [NR_MASTERS-1:0]           busms_hmastlock_o_flat;
  wire [NR_MASTERS-1:0]           busms_hready_i_flat;
  wire [NR_MASTERS-1:0]           busms_hresp_i_flat;

  wire [NR_SLAVES-1:0]           bussl_hsel_o_flat;
  wire [NR_SLAVES-1:0][PLEN-1:0] bussl_haddr_o_flat;
  wire [NR_SLAVES-1:0][XLEN-1:0] bussl_hwdata_o_flat;
  wire [NR_SLAVES-1:0][XLEN-1:0] bussl_hrdata_i_flat;
  wire [NR_SLAVES-1:0]           bussl_hwrite_o_flat;
  wire [NR_SLAVES-1:0][     2:0] bussl_hsize_o_flat;
  wire [NR_SLAVES-1:0][     2:0] bussl_hburst_o_flat;
  wire [NR_SLAVES-1:0][     3:0] bussl_hprot_o_flat;
  wire [NR_SLAVES-1:0][     1:0] bussl_htrans_o_flat;
  wire [NR_SLAVES-1:0]           bussl_hmastlock_o_flat;
  wire [NR_SLAVES-1:0]           bussl_hready_i_flat;
  wire [NR_SLAVES-1:0]           bussl_hresp_i_flat;

  generate
    for (m = 0; m < NR_MASTERS; m = m + 1) begin : gen_busms_flat
      assign busms_hsel_o_flat      [m] = busms_hsel_o      [m];
      assign busms_haddr_o_flat     [m] = busms_haddr_o     [m];
      assign busms_hwdata_o_flat    [m] = busms_hwdata_o    [m];
      assign busms_hrdata_o_flat    [m] = busms_hrdata_o    [m];
      assign busms_hsize_o_flat     [m] = busms_hsize_o     [m];
      assign busms_hburst_o_flat    [m] = busms_hburst_o    [m];
      assign busms_hprot_o_flat     [m] = busms_hprot_o     [m];
      assign busms_htrans_o_flat    [m] = busms_htrans_o    [m];
      assign busms_hmastlock_o_flat [m] = busms_hmastlock_o [m];

      assign busms_hwrite_i [m] = busms_hwrite_i_flat [m];
      assign busms_hready_i [m] = busms_hready_i_flat [m];
      assign busms_hresp_i  [m] = busms_hresp_i_flat  [m];
    end

    for (s = 0; s < NR_SLAVES; s = s + 1) begin : gen_bussl_flat
      assign busms_hsel_i      [s] = busms_hsel_i_flat      [s];
      assign busms_haddr_i     [s] = busms_haddr_i_flat     [s];
      assign busms_hwdata_i    [s] = busms_hwdata_i_flat    [s];
      assign busms_hrdata_i    [s] = busms_hrdata_i_flat    [s];
      assign busms_hsize_i     [s] = busms_hsize_i_flat     [s];
      assign busms_hburst_i    [s] = busms_hburst_i_flat    [s];
      assign busms_hprot_i     [s] = busms_hprot_i_flat     [s];
      assign busms_htrans_i    [s] = busms_htrans_i_flat    [s];
      assign busms_hmastlock_i [s] = busms_hmastlock_i_flat [s];

      assign busms_hwrite_o_flat [s] = busms_hwrite_o [s];
      assign busms_hready_o_flat [s] = busms_hready_o [s];
      assign busms_hresp_o_flat  [s] = busms_hresp_o  [s];
    end
  endgenerate

  generate
    for (c = 1; c < CONFIG.CORES_PER_TILE; c = c + 1) begin
      assign pic_ints_i[c] = 32'h0;
    end
  endgenerate

  localparam MOR1KX_FEATURE_FPU          = (CONFIG.CORE_ENABLE_FPU ? "ENABLED" : "NONE");
  localparam MOR1KX_FEATURE_PERFCOUNTERS = (CONFIG.CORE_ENABLE_PERFCOUNTERS ? "ENABLED" : "NONE");
  localparam MOR1KX_FEATURE_DEBUGUNIT    = "NONE"; // XXX: Enable debug unit with OSD CDM module (once it's ready)

  generate
    for (c = 0; c < CONFIG.CORES_PER_TILE; c = c + 1) begin : gen_cores
      riscv_pu #(
        .XLEN ( XLEN ),
        .PLEN ( PLEN )
      )
      u_core (
        //Common signals
        .HRESETn       ( rst_cpu ),
        .HCLK          ( clk     ),

        //PMA configuration
        .pma_cfg_i     ( pma_cfg_i ),
        .pma_adr_i     ( pma_adr_i ),

        //AHB instruction
        .ins_HSEL      ( busms_hsel_o      [2*c]           ),
        .ins_HADDR     ( busms_haddr_o     [2*c][PLEN-1:0] ),
        .ins_HWDATA    ( busms_hwdata_o    [2*c][XLEN-1:0] ),
        .ins_HRDATA    ( busms_hrdata_i    [2*c][XLEN-1:0] ),
        .ins_HWRITE    ( busms_hwrite_o    [2*c]           ),
        .ins_HSIZE     ( busms_hsize_o     [2*c][     2:0] ),
        .ins_HBURST    ( busms_hburst_o    [2*c][     2:0] ),
        .ins_HPROT     ( busms_hprot_o     [2*c][     3:0] ),
        .ins_HTRANS    ( busms_htrans_o    [2*c][     1:0] ),
        .ins_HMASTLOCK ( busms_hmastlock_o [2*c]           ),
        .ins_HREADY    ( busms_hready_i    [2*c]           ),
        .ins_HRESP     ( busms_hresp_i     [2*c]           ),

        //AHB data
        .dat_HSEL      ( busms_hsel_o      [2*c+1]           ),
        .dat_HADDR     ( busms_haddr_o     [2*c+1][PLEN-1:0] ),
        .dat_HWDATA    ( busms_hwdata_o    [2*c+1][XLEN-1:0] ),
        .dat_HRDATA    ( busms_hrdata_i    [2*c+1]           ),
        .dat_HWRITE    ( busms_hwrite_o    [2*c+1][     2:0] ),
        .dat_HSIZE     ( busms_hsize_o     [2*c+1][     2:0] ),
        .dat_HBURST    ( busms_hburst_o    [2*c+1][     3:0] ),
        .dat_HPROT     ( busms_hprot_o     [2*c+1][     1:0] ),
        .dat_HTRANS    ( busms_htrans_o    [2*c+1]           ),
        .dat_HMASTLOCK ( busms_hmastlock_o [2*c+1]           ),
        .dat_HREADY    ( busms_hready_i    [2*c+1]           ),
        .dat_HRESP     ( busms_hresp_i     [2*c+1]           ),

        //Interrupts Interface
        .ext_nmi       ('0),
        .ext_tint      ('0),
        .ext_sint      ('0),
        .ext_int       ('0),

        //Debug Interface
        .dbg_stall     ('0),
        .dbg_strb      ('0),
        .dbg_we        ('0),
        .dbg_addr      ('0),
        .dbg_dati      ('0),
        .dbg_dato      (),
        .dbg_ack       (),
        .dbg_bp        ()
      );

      assign busms_cab_o [c*2  ] = 1'b0;
      assign busms_cab_o [c*2+1] = 1'b0;

      if (CONFIG.USE_DEBUG == 1) begin : gen_ctm_stm
        osd_stm_mor1kx #(
          .MAX_PKT_LEN (CONFIG.DEBUG_MAX_PKT_LEN)
        )
        u_stm (
          .clk             (clk),
          .rst             (rst_dbg),
          .id              (16'(DEBUG_BASEID + 1 + c*CONFIG.DEBUG_MODS_PER_CORE)),
          .debug_in        (dii_out[1+c*CONFIG.DEBUG_MODS_PER_CORE]),
          .debug_out       (dii_in [1+c*CONFIG.DEBUG_MODS_PER_CORE]),
          .debug_in_ready  (dii_out_ready[1 + c*CONFIG.DEBUG_MODS_PER_CORE]),
          .debug_out_ready (dii_in_ready [1 + c*CONFIG.DEBUG_MODS_PER_CORE]),
          .trace_port      (trace[c])
        );

        osd_ctm_mor1kx #(
          .MAX_PKT_LEN (CONFIG.DEBUG_MAX_PKT_LEN)
        )
        u_ctm (
          .clk             (clk),
          .rst             (rst_dbg),
          .id              (16'(DEBUG_BASEID + 1 + c*CONFIG.DEBUG_MODS_PER_CORE + 1)),
          .debug_in        (dii_out[1 + c*CONFIG.DEBUG_MODS_PER_CORE + 1]),
          .debug_out       (dii_in [1 + c*CONFIG.DEBUG_MODS_PER_CORE + 1]),
          .debug_in_ready  (dii_out_ready[1 + c*CONFIG.DEBUG_MODS_PER_CORE + 1]),
          .debug_out_ready (dii_in_ready [1 + c*CONFIG.DEBUG_MODS_PER_CORE + 1]),
          .trace_port      (trace[c])
        );
      end
    end
  endgenerate

  generate
    if (CONFIG.USE_DEBUG != 0 && CONFIG.DEBUG_DEM_UART != 0) begin : gen_dem_uart
      osd_dem_uart_wb u_dem_uart (
        .clk              (clk),
        .rst              (rst_sys),
        .id               (16'(DEBUG_BASEID + CONFIG.DEBUG_MODS_PER_TILE - 1)),
        .irq              (pic_ints_i[0][2]),
        .debug_in         (dii_out[CONFIG.DEBUG_MODS_PER_TILE - 1]),
        .debug_out        (dii_in [CONFIG.DEBUG_MODS_PER_TILE - 1]),
        .debug_in_ready   (dii_out_ready[CONFIG.DEBUG_MODS_PER_TILE - 1]),
        .debug_out_ready  (dii_in_ready [CONFIG.DEBUG_MODS_PER_TILE - 1]),

        .ahb3_hsel_i      (bussl_hsel_i      [SLAVE_UART]),
        .ahb3_haddr_i     (bussl_haddr_i     [SLAVE_UART][3:0]),
        .ahb3_hwdata_i    (bussl_hwdata_i    [SLAVE_UART]),
        .ahb3_hwrite_i    (bussl_hwrite_i    [SLAVE_UART]),
        .ahb3_hsize_i     (bussl_hsize_i     [SLAVE_UART]),
        .ahb3_hburst_i    (bussl_hburst_i    [SLAVE_UART]),
        .ahb3_hprot_i     (bussl_hprot_i     [SLAVE_UART]),
        .ahb3_htrans_i    (bussl_htrans_i    [SLAVE_UART]),
        .ahb3_hmastlock_i (bussl_hmastlock_i [SLAVE_UART]),

        .ahb3_hrdata_o (bussl_hrdata_o [SLAVE_UART]),
        .ahb3_hready_o (bussl_hready_o [SLAVE_UART]),
        .ahb3_hresp_o  (bussl_hresp_o  [SLAVE_UART])
      );
    end
  endgenerate

  ahb3_bus_b3 #(
    .MASTERS        (NR_MASTERS),
    .SLAVES         (NR_SLAVES),
    .S0_ENABLE      (CONFIG.ENABLE_DM),
    .S0_RANGE_WIDTH (CONFIG.DM_RANGE_WIDTH),
    .S0_RANGE_MATCH (CONFIG.DM_RANGE_MATCH),
    .S1_ENABLE      (CONFIG.ENABLE_PGAS),
    .S1_RANGE_WIDTH (CONFIG.PGAS_RANGE_WIDTH),
    .S1_RANGE_MATCH (CONFIG.PGAS_RANGE_MATCH),
    .S2_RANGE_WIDTH (4),
    .S2_RANGE_MATCH (4'he),
    .S3_ENABLE      (CONFIG.ENABLE_BOOTROM),
    .S3_RANGE_WIDTH (4),
    .S3_RANGE_MATCH (4'hf),
    .S4_ENABLE      (CONFIG.DEBUG_DEM_UART),
    .S4_RANGE_WIDTH (28),
    .S4_RANGE_MATCH (28'h9000000)
  )
  u_bus (
    .clk_i                         (clk),
    .rst_i                         (rst_sys),

    // Outputs
    .s_hsel_o      (bussl_hsel_i_flat),
    .s_haddr_o     (bussl_haddr_i_flat),
    .s_hwdata_o    (bussl_hwdata_i_flat),
    .s_hrdata_o    (bussl_hrdata_i_flat),
    .s_hsize_o     (bussl_hsize_i_flat),
    .s_hburst_o    (bussl_hburst_i_flat),
    .s_hprot_o     (bussl_hprot_i_flat),
    .s_htrans_o    (bussl_htrans_i_flat),
    .s_hmastlock_o (bussl_hmastlock_i_flat),

    .m_hwrite_o (busms_hwrite_i_flat),
    .m_hready_o (busms_hready_i_flat),
    .m_hresp_o  (busms_hresp_i_flat),

    // Inputs
    .m_hsel_i      (busms_hsel_o_flat),
    .m_haddr_i     (busms_haddr_o_flat),
    .m_hwdata_i    (busms_hwdata_o_flat),
    .m_hrdata_i    (busms_hrdata_o_flat),
    .m_hsize_i     (busms_hsize_o_flat),
    .m_hburst_i    (busms_hburst_o_flat),
    .m_hprot_i     (busms_hprot_o_flat),
    .m_htrans_i    (busms_htrans_o_flat),
    .m_hmastlock_i (busms_hmastlock_o_flat),

    .s_hwrite_i (bussl_hwrite_o_flat),
    .s_hready_i (bussl_hready_o_flat),
    .s_hresp_i  (bussl_hresp_o_flat),

    .bus_hold                      (1'b0),
    .snoop_adr_o                   (snoop_adr),
    .snoop_en_o                    (snoop_enable),
    .bus_hold_ack                  ()
  );

  // Unused leftover from an older Wishbone spec version
  assign bussl_cab_i_flat = NR_SLAVES'(1'b0);

  //MAM - WB adapter signals
  logic            mam_dm_hsel_o;
  logic [PLEN-1:0] mam_dm_haddr_o;
  logic [XLEN-1:0] mam_dm_hwdata_o;
  logic [XLEN-1:0] mam_dm_hrdata_i;
  logic            mam_dm_hwrite_o;
  logic [     2:0] mam_dm_hsize_o;
  logic [     2:0] mam_dm_hburst_o;
  logic [     3:0] mam_dm_hprot_o;
  logic [     1:0] mam_dm_htrans_o;
  logic            mam_dm_hmastlock_o;
  logic            mam_dm_hready_i;
  logic            mam_dm_hresp_i;

  if (CONFIG.USE_DEBUG == 1) begin : gen_mam_dm_wb
    //MAM
    osd_mam_wb #(
      .DATA_WIDTH  (32),
      .MAX_PKT_LEN (CONFIG.DEBUG_MAX_PKT_LEN),
      .MEM_SIZE0   (CONFIG.LMEM_SIZE),
      .BASE_ADDR0  (0)
    )
    u_mam_dm_wb (
      .clk_i           (clk),
      .rst_i           (rst_dbg),
      .debug_in        (dii_out[0]),
      .debug_out       (dii_in [0]),
      .debug_in_ready  (dii_out_ready[0]),
      .debug_out_ready (dii_in_ready [0]),

      .id              (16'(DEBUG_BASEID)),

      .hsel_o          (mam_dm_hsel_o),
      .haddr_o         (mam_dm_haddr_o),
      .hwdata_o        (mam_dm_hwdata_o),
      .hwrite_o        (mam_dm_hwrite_o),
      .hsize_o         (mam_dm_hsize_o),
      .hburst_o        (mam_dm_hburst_o),
      .hprot_o         (mam_dm_hprot_o),
      .htrans_o        (mam_dm_htrans_o),
      .hmastlock_o     (mam_dm_hmastlock_o),

      .hrdata_i        (mam_dm_hrdata_i),
      .hready_i        (mam_dm_hready_i),
      .hresp_i         (mam_dm_hresp_i)
    );
  end

  if (CONFIG.ENABLE_DM) begin : gen_mam_ahb3_adapter
    mam_ahb3_adapter #(
      .DW (32),
      .AW (32)
    )
    u_mam_ahb3_adapter_dm (
      .ahb3_mam_hsel_o      (mam_dm_hsel_o),
      .ahb3_mam_haddr_o     (mam_dm_haddr_o),
      .ahb3_mam_hwdata_o    (mam_dm_hwdata_o),
      .ahb3_mam_hwrite_o    (mam_dm_hwrite_o),
      .ahb3_mam_hsize_o     (mam_dm_hsize_o),
      .ahb3_mam_hburst_o    (mam_dm_hburst_o),
      .ahb3_mam_hprot_o     (mam_dm_hprot_o),
      .ahb3_mam_htrans_o    (mam_dm_htrans_o),
      .ahb3_mam_hmastlock_o (mam_dm_hmastlock_o),

      .ahb3_mam_hrdata_i    (mam_dm_hrdata_i),
      .ahb3_mam_hready_i    (mam_dm_hready_i),
      .ahb3_mam_hresp_i     (mam_dm_hresp_i),

      .ahb3_in_clk_i                   (clk),
      .ahb3_in_rst_i                   (rst_sys),

      // Outputs
      .ahb3_out_hsel_i      (ahb3_mem_hsel_i),
      .ahb3_out_haddr_i     (ahb3_mem_haddr_i),
      .ahb3_out_hwdata_i    (ahb3_mem_hwdata_i),
      .ahb3_out_hrdata_i    (ahb3_mem_hrdata_i),
      .ahb3_out_hsize_i     (ahb3_mem_hsize_i),
      .ahb3_out_hburst_i    (ahb3_mem_hburst_i),
      .ahb3_out_hprot_i     (ahb3_mem_hprot_i),
      .ahb3_out_htrans_i    (ahb3_mem_htrans_i),
      .ahb3_out_hmastlock_i (ahb3_mem_hmastlock_i),

      .ahb3_in_hwrite_o (bussl_hwrite_o [SLAVE_DM]),
      .ahb3_in_hready_o (bussl_hready_o [SLAVE_DM]),
      .ahb3_in_hresp_o  (bussl_hresp_o  [SLAVE_DM]),

      // Inputs
      .ahb3_in_hsel_i      (bussl_hsel_i      [SLAVE_DM]),
      .ahb3_in_haddr_i     (bussl_haddr_i     [SLAVE_DM]),
      .ahb3_in_hwdata_i    (bussl_hwdata_i    [SLAVE_DM]),
      .ahb3_in_hrdata_i    (bussl_hrdata_i    [SLAVE_DM]),
      .ahb3_in_hsize_i     (bussl_hsize_i     [SLAVE_DM]),
      .ahb3_in_hburst_i    (bussl_hburst_i    [SLAVE_DM]),
      .ahb3_in_hprot_i     (bussl_hprot_i     [SLAVE_DM]),
      .ahb3_in_htrans_i    (bussl_htrans_i    [SLAVE_DM]),
      .ahb3_in_hmastlock_i (bussl_hmastlock_i [SLAVE_DM]),

      .ahb3_out_hwrite_o (ahb3_mem_hwrite_o),
      .ahb3_out_hready_o (ahb3_mem_hready_o),
      .ahb3_out_hresp_o  (ahb3_mem_hresp_o)
    );
  end
  else begin
    assign mam_dm_hrdata_i = '0;
    assign mam_dm_hready_i = 1'b0;
    assign mam_dm_hresp_i  = 1'b0;

    assign bussl_hrdata_o [SLAVE_DM] = '0;
    assign bussl_hready_o [SLAVE_DM] = 1'b0;
    assign bussl_hresp_o  [SLAVE_DM] = 1'b0;
  end

  if (!CONFIG.ENABLE_PGAS) begin : gen_tieoff_pgas
    assign bussl_hrdata_o [SLAVE_PGAS] = '0;
    assign bussl_hready_o [SLAVE_PGAS] = 1'b0;
    assign bussl_hresp_o  [SLAVE_PGAS] = 1'b0;
  end

  generate
    if ((CONFIG.ENABLE_DM) && (CONFIG.LMEM_STYLE == PLAIN)) begin : gen_sram
      ahb3_sram_sp #(
        .DW             (32),
        .AW             (clog2_width(CONFIG.LMEM_SIZE)),
        .MEM_SIZE_BYTE  (CONFIG.LMEM_SIZE),
        .MEM_FILE       (MEM_FILE),
        .MEM_IMPL_TYPE  ("PLAIN")
      )
      u_ram (
        // Outputs
        .ahb3_hwrite_o (ahb3_ext_hwrite_o);
        .ahb3_hready_o (ahb3_ext_hready_o);
        .ahb3_hresp_o  (ahb3_ext_hresp_o);

        // Inputs
        .ahb3_hsel_i      (ahb3_mem_hsel_i);
        .ahb3_haddr_i     (ahb3_mem_haddr_i[clog2_width(CONFIG.LMEM_SIZE)-1:0]);
        .ahb3_hwdata_i    (ahb3_mem_hwdata_i);
        .ahb3_hrdata_i    (ahb3_mem_hrdata_i);
        .ahb3_hsize_i     (ahb3_mem_hsize_i);
        .ahb3_hburst_i    (ahb3_mem_hburst_i);
        .ahb3_hprot_i     (ahb3_mem_hprot_i);
        .ahb3_htrans_i    (ahb3_mem_htrans_i);
        .ahb3_hmastlock_i (ahb3_mem_hmastlock_i)
      );
    end
    else begin
      assign ahb3_ext_hsel_i      = ahb3_mem_hsel_i;
      assign ahb3_ext_haddr_i     = ahb3_mem_haddr_i;
      assign ahb3_ext_hwdata_i    = ahb3_mem_hwdata_i;
      assign ahb3_ext_hrdata_i    = ahb3_mem_hrdata_i;
      assign ahb3_ext_hsize_i     = ahb3_mem_hsize_i;
      assign ahb3_ext_hburst_i    = ahb3_mem_hburst_i;
      assign ahb3_ext_hprot_i     = ahb3_mem_hprot_i;
      assign ahb3_ext_htrans_i    = ahb3_mem_htrans_i;
      assign ahb3_ext_hmastlock_i = ahb3_mem_hmastlock_i;

      assign ahb3_mem_hwrite_o = ahb3_ext_hwrite_o;
      assign ahb3_mem_hready_o = ahb3_ext_hready_o;
      assign ahb3_mem_hresp_o  = ahb3_ext_hresp_o;
    end
  endgenerate

  networkadapter_ct #(
    .CONFIG   (CONFIG),
    .TILEID   (ID),
    .COREBASE (COREBASE)
  )
  u_na (
    `ifdef OPTIMSOC_CLOCKDOMAINS
    `ifdef OPTIMSOC_CDC_DYNAMIC
    .cdc_conf                     (cdc_conf[2:0]),
    .cdc_enable                   (cdc_enable),
    `endif
    `endif
    .clk                         (clk),
    .rst                         (rst_sys),

    .noc_in_ready                (noc_in_ready),
    .noc_out_flit                (noc_out_flit),
    .noc_out_last                (noc_out_last),
    .noc_out_valid               (noc_out_valid),

    .noc_in_flit                 (noc_in_flit),
    .noc_in_last                 (noc_in_last),
    .noc_in_valid                (noc_in_valid),
    .noc_out_ready               (noc_out_ready),

    .irq                         (pic_ints_i[0][4:3]),

    // Outputs
    .ahb3m_hsel_o      (busms_hsel_o      [NR_MASTERS-1]),
    .ahb3m_haddr_o     (busms_haddr_o     [NR_MASTERS-1]),
    .ahb3m_hwdata_o    (busms_hwdata_o    [NR_MASTERS-1]),
    .ahb3s_hwrite_o    (bussl_hwrite_o    [NR_MASTERS-1]),
    .ahb3m_hsize_o     (busms_hsize_o     [NR_MASTERS-1]),
    .ahb3m_hburst_o    (busms_hburst_o    [NR_MASTERS-1]),
    .ahb3m_hprot_o     (busms_hprot_o     [NR_MASTERS-1]),
    .ahb3m_htrans_o    (busms_htrans_o    [NR_MASTERS-1]),
    .ahb3m_hmastlock_o (busms_hmastlock_o [NR_MASTERS-1]),

    .ahb3m_hrdata_o (busms_hrdata_o [SLAVE_NA]),
    .ahb3s_hready_o (bussl_hready_o [SLAVE_NA]),
    .ahb3s_hresp_o  (bussl_hresp_o  [SLAVE_NA]),

    // Inputs
    .ahb3s_hsel_i      (bussl_hsel_i      [SLAVE_NA]),
    .ahb3s_haddr_i     (bussl_haddr_i     [SLAVE_NA]),
    .ahb3s_hwdata_i    (bussl_hwdata_i    [SLAVE_NA]),
    .ahb3m_hwrite_i    (busms_hwrite_i    [SLAVE_NA]),
    .ahb3s_hsize_i     (bussl_hsize_i     [SLAVE_NA]),
    .ahb3s_hburst_i    (bussl_hburst_i    [SLAVE_NA]),
    .ahb3s_hprot_i     (bussl_hprot_i     [SLAVE_NA]),
    .ahb3s_htrans_i    (bussl_htrans_i    [SLAVE_NA]),
    .ahb3s_hmastlock_i (bussl_hmastlock_i [SLAVE_NA]),

    .ahb3s_hrdata_i (bussl_hrdata_i [NR_MASTERS-1]),
    .ahb3m_hready_i (busms_hready_i [NR_MASTERS-1]),
    .ahb3m_hresp_i  (busms_hresp_i  [NR_MASTERS-1])
  );

  generate
    if (CONFIG.ENABLE_BOOTROM) begin : gen_bootrom
      bootrom u_bootrom (
        .clk                      (clk),
        .rst                      (rst_sys),

        // Outputs
        .ahb3_hrdata_o (bussl_hrdata_o [SLAVE_BOOT]),
        .ahb3_hready_o (bussl_hready_o [SLAVE_BOOT]),
        .ahb3_hresp_o  (bussl_hresp_o  [SLAVE_BOOT]),

        // Inputs
        .ahb3_hsel_i      (bussl_hsel_i      [SLAVE_BOOT]),
        .ahb3_haddr_i     (bussl_haddr_i     [SLAVE_BOOT]),
        .ahb3_hwdata_i    (bussl_hwdata_i    [SLAVE_BOOT]),
        .ahb3_hwrite_i    (bussl_hwrite_i    [SLAVE_BOOT]),
        .ahb3_hsize_i     (bussl_hsize_i     [SLAVE_BOOT]),
        .ahb3_hburst_i    (bussl_hburst_i    [SLAVE_BOOT]),
        .ahb3_hprot_i     (bussl_hprot_i     [SLAVE_BOOT]),
        .ahb3_htrans_i    (bussl_htrans_i    [SLAVE_BOOT]),
        .ahb3_hmastlock_i (bussl_hmastlock_i [SLAVE_BOOT])
      );
    end
    else begin
      assign bussl_hrdata_o [SLAVE_BOOT] = 'x;
      assign bussl_hready_o [SLAVE_BOOT] = 1'b0;
      assign bussl_hresp_o  [SLAVE_BOOT] = 1'b0;
    end
  endgenerate
endmodule
