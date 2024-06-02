package display

import chisel3._
import chisel3.util._

import _root_.util.Flushable

class HUB75IO(val numberOfParallelPanels: Int = 1) extends Bundle {
    val row_a = Output(Bool())
    val row_b = Output(Bool())
    val row_c = Output(Bool())
    val row_d = Output(Bool())
    val row_e = Output(Bool())
    val r = Output(UInt(numberOfParallelPanels.W))
    val g = Output(UInt(numberOfParallelPanels.W))
    val b = Output(UInt(numberOfParallelPanels.W))
    val oe = Output(Bool())
    val lat = Output(Bool())
    val clk = Output(Bool())
}

object HUB75IO {
    def apply(numberOfParallelPanels: Int = 1): HUB75IO = {
        new HUB75IO(numberOfParallelPanels)
    }
}

class PixelBufferIO(bitsPerPixel: Int, numberOfPixels: Int) extends Bundle {
    val address = Output(UInt(log2Ceil(numberOfPixels).W))
    val pixel = Input(UInt(bitsPerPixel.W))
}
object PixelBufferIO {
    def apply(bitsPerPixel: Int, numberOfPixels: Int): PixelBufferIO = {
        new PixelBufferIO(bitsPerPixel, numberOfPixels)
    }
}

class HUB75Controller(width: Int = 64, height: Int = 16, numberOfParallelPanels: Int = 1, clockDivider: Int = 1, pixelComponentBits: Int = 1) extends Module {
    val io = IO(new Bundle{
        val hub75 = HUB75IO(numberOfParallelPanels)
        val panelPixels = Vec(numberOfParallelPanels, PixelBufferIO(3*pixelComponentBits, width*height))
        val startOfFrame = Output(Bool())
        val endOfFrame = Output(Bool())
    })
    val brightnessInitPattern = "b0000011111100000".U(16.W)
    val enableOutputPattern = "b0000001000000000".U(16.W)
    val MAX_PULSE_COUNT = (BigInt(1) << (pixelComponentBits)) - BigInt(1)
    val BASE_OUTPUT_CYCLES = 16
    val FULL_WIDTH_OUTPUT_CYCLES = (BigInt(1) << pixelComponentBits) * BigInt(BASE_OUTPUT_CYCLES)
    object State extends ChiselEnum {
        val Reset, InitBrightness, InitOutput, StartFrame, SetupRow, OutputRow, WaitOutputEnable, NextRow, Running = Value
    }
    
    val state = RegInit(State.Reset)

    val xCounter = RegInit(0.U(log2Ceil(width).W))
    val yCounter = RegInit(0.U(log2Ceil(height).W))
    val oeCounter = RegInit(0.U(log2Ceil(FULL_WIDTH_OUTPUT_CYCLES + 1).W))
    val outputBit = RegInit(0.U(pixelComponentBits.W))
    val nextOECounter = RegInit(0.U(log2Ceil(FULL_WIDTH_OUTPUT_CYCLES + 1).W))
    val latchLine = RegInit(false.B)
    val pixelData = (0 until numberOfParallelPanels).map(_ => (0 until 3).map(_ => RegInit(0.U(pixelComponentBits.W))))
    val rgb = RegInit(VecInit(Seq.fill(3)(0.U(numberOfParallelPanels.W))))
    val address = RegInit(0.U(log2Ceil(width*height).W))
    val rowStartAddress = RegInit(0.U(log2Ceil(width*height).W))
    val clk = RegInit(false.B)
    val clockCounter = RegInit(0.U(Math.max(log2Ceil(clockDivider + 1), 1).W))
    val outPhase = RegInit(false.B)

    // Output start of frame trigger for synchronization.
    io.startOfFrame := state === State.StartFrame
    val endOfFrame = WireDefault(false.B)
    io.endOfFrame := endOfFrame

    io.hub75.clk := clk
    io.hub75.row_a := yCounter(0)
    io.hub75.row_b := yCounter(1)
    io.hub75.row_c := yCounter(2)
    io.hub75.row_d := yCounter(3)
    io.hub75.row_e := (if( height >= 32 ) { yCounter(4) } else { false.B })
    io.hub75.lat := latchLine

    val initializing = state === State.Reset || state === State.InitBrightness || state === State.InitOutput
    io.hub75.oe := oeCounter === 0.U || initializing
    io.hub75.r := rgb(2)
    io.hub75.g := rgb(1)
    io.hub75.b := rgb(0)
    for(panelIndex <- 0 to numberOfParallelPanels - 1) {
        io.panelPixels(panelIndex).address := address
    }

    when(oeCounter > 0.U) {
        oeCounter := oeCounter - 1.U
    }

    val clockEnable = WireDefault(false.B)
    when(state =/= State.Reset) {
        if( clockDivider == 0 ) {
            clk := !clk
            clockEnable := true.B
        } else {
            when( clockCounter === 0.U ) {
                clk := !clk
                clockEnable := true.B
                clockCounter := clockDivider.U
            } .otherwise {
                clockCounter := clockCounter - 1.U
            }
        }
    }

    switch(state) {
        is(State.Reset) {
            address := 0.U
            xCounter := 0.U
            yCounter := 0.U
            oeCounter := 0.U
            latchLine := false.B
            clk := false.B
            clockCounter := 0.U
            outPhase := false.B
            rgb := VecInit(Seq.fill(3)(0.U(numberOfParallelPanels.W)))
            state := State.InitBrightness
        }
        is(State.InitBrightness) {
            when( clockEnable ) {
                when(!clk && !outPhase) {
                    for(component <- 0 to 2) {
                        rgb(component) := VecInit(Seq.fill(numberOfParallelPanels)(brightnessInitPattern(xCounter(3, 0)))).asUInt
                    }
                    latchLine := xCounter > (width - 12).U
                    outPhase := true.B
                } .elsewhen( !clk && outPhase ) {
                    clk := true.B
                } .otherwise {
                    clk := false.B
                    outPhase := false.B
                    xCounter := xCounter + 1.U
                    when( xCounter === (width - 1).U ) {
                        xCounter := 0.U
                        latchLine := false.B
                        state := State.InitOutput
                    }
                }
            }
        }
        is(State.InitOutput) {
            when( clockEnable ) {
                when(!clk && !outPhase) {
                    for(component <- 0 to 2) {
                        rgb(component) := VecInit(Seq.fill(numberOfParallelPanels)(enableOutputPattern(xCounter(3, 0)))).asUInt
                    }
                    latchLine := xCounter > (width - 13).U
                    outPhase := true.B
                } .elsewhen( !clk && outPhase ) {
                    clk := true.B
                } .otherwise {
                    outPhase := false.B
                    xCounter := xCounter + 1.U
                    when( xCounter === (width - 1).U ) {
                        // Keep clk high
                        clk := true.B
                        xCounter := 0.U
                        latchLine := false.B
                        state := State.StartFrame
                    } .otherwise {
                        clk := false.B
                    }
                }
            }
        }
        is(State.StartFrame) {
            address := 0.U
            yCounter := 0.U
            state := State.SetupRow
        }
        is(State.SetupRow) {
            xCounter := 0.U
            clk := false.B
            rowStartAddress := address
            outputBit := (1 << (pixelComponentBits - 1)).U
            nextOECounter := FULL_WIDTH_OUTPUT_CYCLES.U
            state := State.OutputRow
        }
        is(State.OutputRow) {
            when( clockEnable ) {
                when(clk) { // falling edge
                    latchLine := false.B    // Deassert the LAT signal every clk cycle.
                    val rgbData = Wire(Vec(3, Vec(numberOfParallelPanels, Bool())))
                    for(panelIndex <- 0 until numberOfParallelPanels) {
                        for(component <- 0 to 2) {
                            rgbData(component)(panelIndex) := (pixelData(panelIndex)(component) & outputBit) =/= 0.U
                        }
                    }
                    for(component <- 0 to 2) {
                        rgb(component) := rgbData(component).asUInt
                    }
                    when( xCounter === (width - 1).U ) {
                        xCounter := 0.U
                        latchLine := true.B
                        state := State.WaitOutputEnable
                    } .otherwise {
                        xCounter := xCounter + 1.U
                    }
                } .otherwise {  // rising edge
                    for(panelIndex <- 0 until numberOfParallelPanels) {
                        for(component <- 0 to 2) {
                            pixelData(panelIndex)(component) := io.panelPixels(panelIndex).pixel(pixelComponentBits*(component+1)-1, pixelComponentBits*component)
                        }
                    }
                    address := address + 1.U
                }
            }
        }
        is(State.WaitOutputEnable) {
            when( clockEnable ) {
                when(clk) { // falling edge
                    latchLine := false.B    // Deassert the LAT signal every clk cycle.
                    when( oeCounter === 0.U ) {
                        oeCounter := nextOECounter
                        nextOECounter := nextOECounter >> 1
                        outputBit := outputBit >> 1
                        when( outputBit === 1.U ) {
                            state := State.NextRow
                            rowStartAddress := rowStartAddress + width.U
                        } .otherwise {
                            address := rowStartAddress
                            state := State.OutputRow
                        }
                    }
                }
            }
        }
        is(State.NextRow) {
            when( yCounter === (height - 1).U ) {
                state := State.StartFrame
                endOfFrame := true.B
            } .otherwise {
                yCounter := yCounter + 1.U
                state := State.SetupRow
            }
        }
    }
}