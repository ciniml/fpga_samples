package display

import chisel3._
import chisel3.util._
import chisel3.experimental.ChiselEnum
import _root_.util.Flushable

class HUB75IO(val numberOfParallelPanels: Int = 1) extends Bundle {
    val row_a = Output(Bool())
    val row_b = Output(Bool())
    val row_c = Output(Bool())
    val row_d = Output(Bool())
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

class HUB75Controller(numberOfParallelPanels: Int = 1) extends Module {
    val io = IO(new Bundle{
        val hub75 = HUB75IO(numberOfParallelPanels)
        val panelPixels = Vec(numberOfParallelPanels, PixelBufferIO(3, 64*16))
    })

    val width = 64
    val height = 16
    val outputEnableWidth = 8

    val brightnessInitPattern = "b0000011111100000".U(16.W)
    val enableOutputPattern = "b0000001000000000".U(16.W)

    object State extends ChiselEnum {
        val Reset, InitBrightness, InitOutput, Running = Value
    }
    
    val state = RegInit(State.Reset)

    val xCounter = RegInit(0.U(log2Ceil(width).W))
    val yCounterNext = RegInit(0.U(log2Ceil(height).W))
    val yCounter = RegInit(0.U(log2Ceil(height).W))
    val oeCounter = RegInit(0.U(log2Ceil(outputEnableWidth).W))
    val latchLine = RegInit(false.B)
    val rgb = RegInit(VecInit(Seq.fill(3)(0.U(numberOfParallelPanels.W))))
    val address = RegInit(0.U(log2Ceil(width*height).W))
    val clk = RegInit(false.B)
    val outPhase = RegInit(false.B)

    io.hub75.clk := clk
    io.hub75.row_a := yCounter(0)
    io.hub75.row_b := yCounter(1)
    io.hub75.row_c := yCounter(2)
    io.hub75.row_d := yCounter(3)
    io.hub75.lat := latchLine
    io.hub75.oe := oeCounter > 0.U || state =/= State.Running
    io.hub75.r := rgb(2)
    io.hub75.g := rgb(1)
    io.hub75.b := rgb(0)
    for(panelIndex <- 0 to numberOfParallelPanels - 1) {
        io.panelPixels(panelIndex).address := address
    }

    when(oeCounter > 0.U) {
        oeCounter := oeCounter - 1.U
    }

    switch(state) {
        is(State.Reset) {
            address := 0.U
            xCounter := 0.U
            yCounter := 0.U
            oeCounter := 0.U
            latchLine := false.B
            clk := false.B
            outPhase := false.B
            rgb := VecInit(Seq.fill(3)(0.U(numberOfParallelPanels.W)))
            state := State.InitBrightness
        }
        is(State.InitBrightness) {
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
        is(State.InitOutput) {
            when(!clk && !outPhase) {
                for(component <- 0 to 2) {
                    rgb(component) := VecInit(Seq.fill(numberOfParallelPanels)(enableOutputPattern(xCounter(3, 0)))).asUInt
                }
                latchLine := xCounter > (width - 13).U
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
                    state := State.Running
                }
            }
        }
        is(State.Running) {
            latchLine := false.B
            for(component <- 0 to 2) {
                rgb(component) := Cat((0 to numberOfParallelPanels-1).map(panelIndex => io.panelPixels(panelIndex).pixel(component).asUInt).reverse)
            }
            clk := !clk
            when(!clk) {
                address := address + 1.U
                when( xCounter === (width - 1).U ) {
                    xCounter := 0.U
                    latchLine := true.B
                    oeCounter := (outputEnableWidth - 1).U
                    when( yCounterNext === (height - 1).U ) {
                        address := 0.U
                        yCounterNext := 0.U
                    } .otherwise {
                        yCounterNext := yCounterNext + 1.U
                    }
                    yCounter := yCounterNext
                } .otherwise {
                    xCounter := xCounter + 1.U
                }
            }
        }
    }
}