package system

import chisel3._
import chisel3.util._
import chisel3.experimental.chiselName
import uart._

@chiselName
class UartSystem() extends RawModule {
  val clock = IO(Input(Clock()))
  val resetn = IO(Input(Bool()))
  val tx = IO(Output(Bool()))
  val rx = IO(Input(Bool()))
  
  withClockAndReset(clock, !resetn) {
    val clockFreq = 24000000  // 24MHz
    val baudRate = 115200
    val uartRx = Module(new UartRx(8, clockFreq / baudRate, 3))
    val uartTx = Module(new UartTx(8, clockFreq / baudRate))

    uartRx.io.out <> uartTx.io.in

    tx <> uartTx.io.tx
    rx <> uartRx.io.rx
  }
}

object Elaborate extends App {
  Driver.execute(Array(
    "-tn=uartsystem",
    "-td=rtl/chisel/uart",
    // "--full-stacktrace",
  ),
  () => new UartSystem)
}