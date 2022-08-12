ThisBuild / scalaVersion     := "2.12.12"
ThisBuild / version          := "0.1.0"
ThisBuild / organization     := "org.fugafuga"

lazy val commonSettings = Seq (
  libraryDependencies ++= Seq(
    "edu.berkeley.cs" %% "chisel3" % "3.4.3",
    "edu.berkeley.cs" %% "chiseltest" % "0.3.2" % "test"
  ),
  scalacOptions ++= Seq(
    "-Xsource:2.11",
    "-language:reflectiveCalls",
    "-deprecation",
    "-feature",
    "-Xcheckinit"
  ),
  addCompilerPlugin("edu.berkeley.cs" % "chisel3-plugin" % "3.4.3" cross CrossVersion.full),
  addCompilerPlugin("org.scalamacros" % "paradise" % "2.1.1" cross CrossVersion.full)
)

lazy val riscv_chisel_book = (project in file("./external/riscv-chisel-book/chisel-template")).
  settings(
    commonSettings,
    name := "riscv_chisel_book"
  )
  
lazy val fpga_samples = (project in file("./chisel")).
  settings(
    commonSettings,
    name := "fpga_samples"
  )
  .dependsOn(riscv_chisel_book)

lazy val root = (project in file("."))
  .aggregate(fpga_samples, riscv_chisel_book)
