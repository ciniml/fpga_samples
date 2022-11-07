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