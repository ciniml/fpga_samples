package util

import chisel3._
import chisel3.util._

class MultiByteSymbol(val numberOfBytes: Int) extends Bundle {
    val numberOfBits = (numberOfBytes*8)
    val data = UInt(numberOfBits.W)
    val keep = UInt(numberOfBytes.W)
    val last = Bool()
}
object MultiByteSymbol {
    def apply(numberOfBytes: Int): MultiByteSymbol = {
        new MultiByteSymbol(numberOfBytes)
    }
    def apply(flushable: Flushable[UInt]): MultiByteSymbol = {
        val bitWidth = flushable.data.getWidth
        val byteWidth = bitWidth / 8
        assert((bitWidth % 8) == 0)
        val hw = Wire(new MultiByteSymbol(byteWidth))
        hw.data := flushable.data
        hw.keep := Fill(byteWidth, 1.U(1.W))
        hw.last := flushable.last
        hw
    }
}
class MultiByteSymbolWithMetadata[T <: Data](val numberOfBytes: Int, metadataGen: T) extends Bundle {
    val numberOfBits = (numberOfBytes*8)
    val data = UInt(numberOfBits.W)
    val keep = UInt(numberOfBytes.W)
    val metadata = metadataGen.cloneType.asInstanceOf[T]
    val last = Bool()
}
object MultiByteSymbolWithMetadata {
    def apply[T <: Data](numberOfBytes: Int, genMetadata: T): MultiByteSymbolWithMetadata[T] = {
        new MultiByteSymbolWithMetadata(numberOfBytes, genMetadata)
    }
}