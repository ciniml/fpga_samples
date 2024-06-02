ThisBuild / scalaVersion     := "2.13.12"
ThisBuild / version          := "0.1.0"
ThisBuild / organization     := "org.fugafuga"

lazy val commonSettings = Seq (
  libraryDependencies ++= Seq(
    "org.chipsalliance" %% "chisel" % "6.2.0",
    "org.scalatest" %% "scalatest" % "3.2.16" % "test"
  ),
  scalacOptions ++= Seq(
    "-language:reflectiveCalls",
    "-deprecation",
    "-feature",
    "-Xcheckinit",
    "-Ymacro-annotations"
  ),
  addCompilerPlugin("org.chipsalliance" % "chisel-plugin" % "6.2.0" cross CrossVersion.full),
)

// lazy val riscv_chisel_book = (project in file("./external/riscv-chisel-book/chisel-template")).
//   settings(
//     commonSettings,
//     name := "riscv_chisel_book"
//   )
  
lazy val fpga_samples = (project in file("./chisel")).
  settings(
    commonSettings,
    name := "fpga_samples"
  )
  
// lazy val root = (project in file("."))
//   .aggregate(fpga_samples, riscv_chisel_book)
