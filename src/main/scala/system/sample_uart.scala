package system

import chisel3._
import chisel3.util._
import chisel3.experimental.chiselName

@chiselName
class UartSystem() extends Module {
  val io = IO(new Bundle{
    val tx = Output(Bool())
  })
  
}

object Elaborate extends App {
  Driver.execute(Array(
    "-tn=video_generator",
    "-td=rtl/chiselName"
  ),
  () => new UartSystem)
}