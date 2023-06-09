% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/OptimusExamples.R
\name{OptimusExamples}
\alias{OptimusExamples}
\title{Generate script for reproducing a tutorial}
\usage{
OptimusExamples(
  dir,
  example = 1,
  method = "SA",
  file_name = "example.R",
  mopac = NULL,
  vignette = TRUE
)
}
\arguments{
\item{dir}{String specifying directory where to save the script
and vignette.}

\item{example}{Integer specifying tutorial or example number based on
manual (default value is 1).}

\item{method}{String specifying which optimisation protocol to use.
Enter "SA" for Simulated Annealing or "RE" for Replica
Exchange (default value is "SA").}

\item{file_name}{String specifying file name of script (default value is
example.R).}

\item{mopac}{String specifying the path of the MOPAC (Molecular Orbital
PACkage) executable for tutorial 3 (Geometry Optimisation
of Vitamin C Molecule) (default value is NULL).}

\item{vignette}{If TRUE, add tutorial vignette to directory (default
value is TRUE).}
}
\value{
A script (and optionally a vignette) for reproducing a tutorial.
}
\description{
Generate script for reproducing a tutorial
}
\examples{

out.dir <- tempdir()
OptimusExamples(dir=out.dir, example=1)
}
