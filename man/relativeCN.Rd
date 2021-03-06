\name{relativeCN}
\alias{relativeCN}
\alias{relativeCN,data.frame,matrix-method}
\alias{relativeCN,GRanges,matrix-method}
\title{Calculate and Segment Relative Copy Number From Sequencing Counts}
\description{This function uses the \code{\link{GCadjustCopy}} function to convert
  a matrix of count data into absolute copy number estimates, then calculates the log2
  fold change ratio and segments these values.
}
\usage{
  \S4method{relativeCN}{data.frame,matrix}(input.windows, input.counts, gc.params = NULL,
                                          ..., verbose = TRUE)
  \S4method{relativeCN}{GRanges,matrix}(input.windows, input.counts, gc.params = NULL,
                                        ..., verbose = TRUE)
}
\arguments{
  \item{input.windows}{A \code{data.frame} with (at least) columns \code{chr},
                       \code{start}, and \code{end}, or a GRanges object.}
  \item{input.counts}{A matrix of counts. The first column must be for the control
                      state, and the second column must be for the treatment state.}
  \item{gc.params}{A \code{\linkS4class{GCAdjustParams}} object, holding parameters
                   related to mappability and GC content correction of read counts, or NULL,
                   if GC content correction is not desired.}
  \item{...}{Further parameters passed to \code{\link{segment}} function in \code{DNAcopy}
             package, and also the \code{segment.sqrt} parameter to \code{\link{absoluteCN}}.}
  \item{verbose}{Whether to print the progess of processing.}
}
\details{
  The algorithm used to call the copy number regions is Circular Binary
  Segmentation (Olshen et al. 2004). Weights for each window, that are the inverse of
  the variance, calculated with the delta method, are always used. Windows or regions
  that were not in the segmentation result are given the value \code{NA}.

  If \code{gc.params} is \code{NULL}, then no correction for mappability
  or GC content is done. This can be done when the bias in both treatment and control
  samples is assumed to be equal. If \code{gc.params} is specified, then absolute
  copy numbers are estimated with \code{\link{GCadjustCopy}} for each condition,
  which corrects for mappability and then GC content, before estimating absolute
  copy numbers. The ratio of estimated absolute copy numbers is segmented, to
  calculate relative copy numbers.
}
\value{
  If \code{gc.params} was given, then a \code{\linkS4class{AdjustedCopyEstimate}} object.
  Otherwise, a \code{\linkS4class{CopyEstimate}} object. The copy number ratios are
  on the linear scale, not log2.
}
\author{Dario Strbenac}
\references{Olshen, A. B., Venkatraman, E. S., Lucito, R., and Wigler, M. (2004).
  Circular binary segmentation for the analysis of array-based DNA copy number data.
  \emph{Biostatistics} 5: 557-572}
\examples{
  inputs <- data.frame(chr = c("chr1", "chr1", "chr1", "chr2", "chr2"),
                     start = c(1, 50001, 100001, 1, 10001),
                       end = c(50000, 100000, 150000, 10000, 20000))
  counts <- matrix(c(25, 39, 3, 10, 22, 29, 38, 5, 19, 31), nrow = 5)
  colnames(counts) <- c("Control", "Treatment")
  relativeCN(inputs, input.counts = counts, p.method = "perm")
}
