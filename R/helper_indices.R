#' Helper Functions for `compute_orderwise`
#'
#' These functions are designed to be used as the `func` parameter in the `compute_orderwise` function.
#' They calculate various metrics, including distances, dissimilarities, correlations, and mutual information.
#'
#' @import data.table
#' @importFrom geosphere distHaversine
#' @importFrom vegan vegdist
#' @importFrom cluster daisy
#' @importFrom reshape2 melt
#' @importFrom entropy mi.plugin

# Verify required packages
required_packages <- c("geosphere", "vegan", "cluster", "reshape2", "entropy")
lapply(required_packages, function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Package '", pkg, "' is required but not installed.")
})

# DISTANCE BETWEEN SITES
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# !! CURRENTLY DOESN'T WORK WITH `compute_orderwise` !!

#' Calculate Distance Between Sites
#'
#' @param df A data frame containing site coordinates.
#' @param site_col The column name representing site IDs.
#' @param vec_from The site ID or vector for the starting site.
#' @param vec_to The site ID or vector for the destination site(s).
#'
#' @return Distance(s) in meters between the specified sites.
#' @export
#'
distance <- function(df, site_col, vec_from, vec_to = NULL) {
  library(geosphere)

  # Subset 'from' data
  site_from_data <- df[df[[site_col]] == vec_from, c("x", "y"), drop = FALSE]

  # Handle missing or invalid inputs
  if (nrow(site_from_data) == 0) stop("Invalid 'from' site ID: ", vec_from)

  if (is.null(vec_to)) {
    stop("Order = 1 calculations are not supported for the distance function.")
  } else if (length(vec_to) == 1) {
    # Pairwise comparison
    site_to_data <- df[df[[site_col]] == vec_to, c("x", "y"), drop = FALSE]
    if (nrow(site_to_data) == 0) stop("Invalid 'to' site ID: ", vec_to)
    return(distHaversine(site_from_data, site_to_data))
  } else {
    # Higher-order comparisons
    site_to_data <- df[df[[site_col]] %in% vec_to, c("x", "y"), drop = FALSE]
    if (nrow(site_to_data) == 0) stop("Invalid 'to' site IDs: ", paste(vec_to, collapse = ", "))
    distances <- apply(site_to_data, 1, function(to_coords) {
      distHaversine(site_from_data, to_coords)
    })
    # Ensure output is scalar
    return(sum(distances, na.rm = TRUE))
  }
}

# !! WORKS AS STANDALONE FUNCTION I.E. NOT WITH `compute_orderwise` !!
# Function to calculate pairwise distances using distm
#' Calculate Pairwise Distance Matrix
#'
#' @param data A data frame containing site coordinates and IDs.
#' @param distance_fun The distance function to use (default: `distGeo`).
#'
#' @return A data frame containing pairwise distances between sites.
#' @export
#'
calculate_pairwise_distances_matrix <- function(data, distance_fun = distGeo) {
  if (!all(c("grid_id", "x", "y") %in% colnames(data))) {
    stop("Data frame must contain 'grid_id', 'x', and 'y' columns.")
  }

  distance_matrix <- distm(data[, c("x", "y")], fun = distance_fun) / 1000  # Convert to km
  distances <- as.data.frame(as.table(distance_matrix))
  colnames(distances) <- c("site_from_index", "site_to_index", "value")

  distances$site_from <- data$grid_id[distances$site_from_index]
  distances$site_to <- data$grid_id[distances$site_to_index]

  distances <- distances[distances$site_from != distances$site_to, ]
  return(distances[, c("site_from", "site_to", "value")])
}

# SPECIES RICHNESS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' Calculate Species Richness
#'
#' @param vec_from A numeric vector representing species counts at the first site.
#' @param vec_to (Optional) A numeric vector for pairwise or higher-order comparisons.
#'
#' @return The species richness value.
#' @export
#'
richness <- function(vec_from, vec_to = NULL) {
  if (is.null(vec_to)) {
    return(sum(vec_from != 0, na.rm = TRUE))
  } else if (length(vec_from) > 1 && length(vec_to) > 1) {
    return(abs(sum(vec_from != 0, na.rm = TRUE) - sum(vec_to != 0, na.rm = TRUE)))
  } else {
    return(NA)
  }
}


# SPECIES TURNOVER (BETA DIVERSITY)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' Calculate Species Turnover or Beta Diversity
#'
#' @param vec_from A numeric vector representing species counts at the first site.
#' @param vec_to (Optional) A numeric vector for pairwise or higher-order comparisons.
#'
#' @return The species turnover value.
#' @export
#'
turnover <- function(vec_from, vec_to = NULL) {
  if (is.null(vec_to)) {
    stop("Turnover calculation requires both vec_from and vec_to.")
  } else if (length(vec_from) > 1 && length(vec_to) > 1) {
    # Calculate species turnover
    total_species <- sum((vec_from != 0 | vec_to != 0), na.rm = TRUE) # Identifies all species present in either vec_from or vec_to
    shared_species <- sum((vec_from != 0 & vec_to != 0), na.rm = TRUE) # Identifies species shared between vec_from and vec_to
    turnover <- (total_species - shared_species) / total_species # calculates the proportion of species not shared relative to the total number of species present
    return(turnover)
  } else {
    return(NA)
  }
}

# Min: 0.0000: Indicates complete similarity (no turnover).
# >> All species present at site_from are also present at site_to, and vice versa.
# Max: 1.0000: Indicates complete turnover (no shared species).
# >> All species present at site_from are absent at site_to and vice versa.

# 1st Qu.: 0.9778, Median: 1.0000, 3rd Qu.: 1.0000:
# >> The species turnover is very high in most site pairs, as the majority of values
# are close to or equal to 1.
# This suggests that most sites have few or no shared species, which could indicate
# high species heterogeneity across the landscape.
# Mean: 0.9807:
# >> The average turnover across all site pairs is approximately 98%.
# >> This reinforces the observation that most sites have a high degree of dissimilarity
# >> in their species composition.

# SPECIES ABUNDANCE
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' Calculate Species Abundance
#'
#' @param vec_from A numeric vector representing species counts at the first site.
#' @param vec_to (Optional) A numeric vector for pairwise or higher-order comparisons.
#'
#' @return The species abundance value.
#' @export
#'
abund <- function(vec_from, vec_to = NULL) {
  if (is.null(vec_to)) {
    return(sum(vec_from, na.rm = TRUE))
  } else if (length(vec_from) > 1 && length(vec_to) > 1) {
    return(abs(sum(vec_from, na.rm = TRUE) - sum(vec_to, na.rm = TRUE)))
  } else {
    return(NA)
  }
}

# PHI COEFFICIENT (PRESENCE-ABSENCE)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' Calculate Phi Coefficient
#'
#' @param vec_from A binary presence-absence vector for the first site.
#' @param vec_to A binary presence-absence vector for the second site.
#'
#' @return The Phi Coefficient value.
#' @export
#'
phi_coef <- function(vec_from, vec_to) {
  data_i <- as.numeric(vec_from > 0)
  data_j <- as.numeric(vec_to > 0)

  A <- sum(data_i == 1 & data_j == 1)
  B <- sum(data_i == 1 & data_j == 0)
  C <- sum(data_i == 0 & data_j == 1)
  D <- sum(data_i == 0 & data_j == 0)

  denominator <- sqrt((A + B) * (A + C) * (B + D) * (C + D))
  if (is.na(denominator) || denominator == 0) {
    return(NA)
  }

  return((A * D - B * C) / denominator)
}

# Phi Coefficient (Presence-Absence Data):
# Measures the strength of association between species pairs,
# ranging from -1 (perfect negative association) to +1 (perfect positive association)

# --> Intrepretting plots:
# -1 = perfect negative association (species never co-occur)
# 0 = no association (species co-occur randomly).
# +1 = perfect positive association (species always co-occur)
# In plot, if mean Phi values are all very close to 0 = on average,
# there is little to no strong co-occurrence signal across sites.

# SPEARMAN'S RANK CORRELATION (ABUNDANCES)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' Calculate Spearman's Rank Correlation
#'
#' @param vec_from A numeric vector representing species abundances at the first site.
#' @param vec_to A numeric vector representing species abundances at the second site.
#'
#' @return Spearman's rank correlation coefficient.
#' @export
#'
cor_spear <- function(vec_from, vec_to) {
  if (length(vec_from) > 1 && length(vec_to) > 1) {
    return(cor(vec_from, vec_to, method = "spearman", use = "pairwise.complete.obs"))
  } else {
    return(NA)
  }
}

# Spearman’s Rank Correlation (Abundance Data):
# Measures the rank-based association between species pairs, also ranging from -1 to +1.
# >> Description: Measures the strength and direction of a monotonic association between two species' abundances.
# >> When to Use: When data is non-parametric/doesn't meet assumptions of normality.
# It is based on ranks i.e. is robust to outliers.
# >> Interpretation: Ranges from −1 (perfect negative correlation) to
# 1 (perfect positive correlation), with 0 indicating no association.

# --> Intrepretting plots:
# High Mean Spearman Values (Red) = strong positive associations between
# species abundances at the site (e.g., species tend to have similar abundance patterns).
# Low Mean Spearman Values (Green) = weak or negative associations
# (e.g., species have dissimilar abundance patterns).
# Near-Zero Mean Spearman Values = species abundances not correlated at site
# (random or neutral associations).

# PEARSON'S CORRELATION
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' Calculate Pearson's Correlation
#'
#' @param vec_from A numeric vector representing species abundances at the first site.
#' @param vec_to A numeric vector representing species abundances at the second site.
#'
#' @return Pearson's correlation coefficient.
#' @export
#'
cor_pears <- function(vec_from, vec_to) {
  if (length(vec_from) > 1 && length(vec_to) > 1) {
    return(cor(vec_from, vec_to, method = "pearson", use = "pairwise.complete.obs"))
  } else {
    return(NA)
  }
}

# >> Description: Measures the linear association between two species' abundances.
# >> When to Use: When the data is normally distributed and you are interested in
# linear relationships.
# >> Interpretation: Similar to Spearman’s, it ranges from −1 to 1.


# BRAY-CURTIS DISSIMILARITY
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' Calculate Bray-Curtis Dissimilarity
#'
#' @param vec_from A numeric vector representing species abundances at the first site.
#' @param vec_to A numeric vector for species abundances at the second site.
#'
#' @return The Bray-Curtis dissimilarity value.
#' @export
#'
diss_bcurt <- function(vec_from, vec_to) {
  if (length(vec_from) > 1 && length(vec_to) > 1) {
    return(vegan::vegdist(rbind(vec_from, vec_to), method = "bray")[1])
  } else {
    return(NA)
  }
}

# >> Description: Measures the dissimilarity between two samples based on species abundances.
# Ranges from 0 (identical) to 1 (completely dissimilar).
# >> When to Use: Quantify dissimilarity based on abundance data, taking into account
# the differences in species counts.
# >> Interpretation: Close to 0 indicates high similarity, value close to
# 1 indicates high dissimilarity.

# GOWER'S SIMILARITY
# !! CURRENTLY DOESN'T WORK WITH `compute_orderwise` !!
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' Calculate Gower's Dissimilarity
#'
#' @param vec_from A numeric or categorical vector for the first site.
#' @param vec_to A numeric or categorical vector for the second site.
#'
#' @return The Gower dissimilarity value.
#' @export
#'
gower_dissimilarity <- function(vec_from, vec_to) {
  if (length(vec_from) > 1 && length(vec_to) > 1) {
    comb_df <- data.frame(t(rbind(vec_from, vec_to)))
    diss_mat <- as.matrix(cluster::daisy(comb_df, metric = "gower"))
    return(diss_mat[1, 2])
  } else {
    return(NA)
  }
}

# >> Description: Versatile measure that can handle both continuous and categorical data.
# Calculates similarity between two samples based on attributes.
# >> When to Use: When your data includes different types of variables
# (e.g., abundance, presence/absence, and categorical data)
# >> Interpretation: Ranges from 0 (no similarity) to 1 (complete similarity).

# Low Dissimilarity (Close to 0): The two vectors (vec_from and vec_to) are very similar
# For numeric attributes, their values are close, and categorical attributes match frequently.
# High Dissimilarity (Close to 1): The two vectors are very different
# Intermediate Values (Between 0 and 1)


# Function to calculate pairwise Gower dissimilarities
#' Calculate Pairwise Gower Dissimilarity Matrix
#'
#' @param df A data frame containing site information.
#' @param sp_cols A vector of column names for species data.
#'
#' @return A data frame containing pairwise Gower dissimilarities between sites.
#' @export
#'
calculate_pairwise_gower_dist_matrix <- function(df, sp_cols) {
  sbs_gower_df <- as.data.frame(as.matrix(cluster::daisy(df[, sp_cols], metric = "gower", stand = FALSE)))
  sbs_gower_df$site_from <- row.names(sbs_gower_df)
  sbs_gower_melt <- reshape2::melt(sbs_gower_df, id.vars = "site_from", variable.name = "site_to", value.name = "value")

  # Exclude self-pairs
  sbs_gower_melt <- sbs_gower_melt[sbs_gower_melt$site_from != sbs_gower_melt$site_to, ]
  sbs_gower_melt$x <- df$x[match(sbs_gower_melt$site_from, df$grid_id)]
  sbs_gower_melt$y <- df$y[match(sbs_gower_melt$site_from, df$grid_id)]

  return(sbs_gower_melt)
}


# MUTUAL INFORMATION
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' Calculate Mutual Information
#'
#' @param vec_from A numeric or categorical vector for the first variable.
#' @param vec_to A numeric or categorical vector for the second variable.
#'
#' @return The mutual information value between the two variables.
#' @export
#'
mutual_info <- function(vec_from, vec_to) {
  library(entropy)
  if (length(vec_from) > 1 && length(vec_to) > 1) {
    joint_dist <- table(vec_from, vec_to)
    mi <- mi.plugin(joint_dist)
    return(mi)
  } else {
    return(NA)
  }
}

# >> Description: A non-parametric measure of mutual dependence between two variables
# i.e. captures both linear and non-linear associations
# >> When to Use: When you suspect non-linear relationships or want a flexible measure of association.
# >> Interpretation: Higher values indicate stronger associations.
# Does not have fixed range but is always non-negative.

# Non-Negative Values (≥ 0)
# A value of 0 means the two variables are independent (no shared information).
# Higher values indicate greater dependency or shared information between the two variables.
