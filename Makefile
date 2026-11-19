TOP   := noc_mesh
RTL   := rtl/noc_fifo.sv rtl/noc_router.sv rtl/noc_mesh.sv
TB    := tb/tb_noc.sv
BUILD := build
RATES ?= 5 10 20 30 40 60 90

.PHONY: test sweep lint synth clean

$(BUILD)/tb.vvp: $(RTL) $(TB)
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $@ $(RTL) $(TB)

# Functional regression at light, medium and saturating load.
test: $(BUILD)/tb.vvp
	vvp -n $(BUILD)/tb.vvp +rate=10 +stall=10
	vvp -n $(BUILD)/tb.vvp +rate=40 +stall=30
	vvp -n $(BUILD)/tb.vvp +rate=90 +stall=50

# Latency-vs-load curve.
sweep: $(BUILD)/tb.vvp
	@for r in $(RATES); do vvp -n $(BUILD)/tb.vvp +rate=$$r +stall=0 | grep RESULT; done

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT --top-module $(TOP) $(RTL)

synth:
	@mkdir -p $(BUILD)
	yosys -q -p "read_verilog -sv $(RTL); synth -top noc_router; tee -o $(BUILD)/synth_stat.txt stat"

clean:
	rm -rf $(BUILD)
