ThisBuild / scalaVersion     := "2.13.8"
ThisBuild / version          := "0.1.0"
ThisBuild / organization     := "org.fugafuga"

lazy val commonSettings = Seq (
  libraryDependencies ++= Seq(
    "edu.berkeley.cs" %% "chisel3" % "3.5.4",
    "edu.berkeley.cs" %% "chiseltest" % "0.5.4" % "test",
  ),
  scalacOptions ++= Seq(
    "-language:reflectiveCalls",
    "-deprecation",
    "-feature",
    "-Xcheckinit",
    "-Ymacro-annotations"
  ),
  addCompilerPlugin("edu.berkeley.cs" % "chisel3-plugin" % "3.5.4" cross CrossVersion.full),

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
