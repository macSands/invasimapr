% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/predict_dissim.R
\name{predict_dissim}
\alias{predict_dissim}
\title{Predict Dissimilarity Using Environmental Data}
\usage{
predict_dissim(
  block_sp,
  sbe_scaled,
  zeta_model,
  mean_rich,
  mean_turn,
  sbs_xy,
  rsa
)
}
\arguments{
\item{block_sp}{Data frame containing geographic and environmental data.}

\item{sbe_scaled}{Scaled environmental predictors.}

\item{zeta_model}{Model object from \code{zetadiv::Zeta.msgdm}.}

\item{mean_rich}{Data frame with mean richness values for calibration.}

\item{mean_turn}{Data frame with mean turnover values for calibration.}

\item{sbs_xy}{Data frame with spatial coordinates.}

\item{rsa}{Spatial object for overlaying boundaries on plots.}
}
\value{
A data frame with predicted dissimilarity and other metrics.
}
\description{
This function predicts turnover or zeta diversity values using models from \code{zetadiv::Zeta.msgdm} and new environmental data.
}
\examples{
# Example usage:
result <- predict_dissim(block_sp, sbe_scaled, zeta_model, mean_rich, mean_turn, sbs_xy, rsa)
head(result)

}
