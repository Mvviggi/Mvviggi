#NEON Tutorial
#Explore and work with NEON biodiversity data from aquatic ecosystems

# load libraries 
library(tidyverse)
library(neonOS)
library(neonUtilities)
library(neonOS)
library(vegan)
library(dplyr)
library(ggplot2)
# clean out workspace

rm(list = ls()) # OPTIONAL - clear out your environment
gc()            # Uncomment these lines if desired

# Sys.setenv(FULCRUM_TOKEN="26165948843ae921af9c0d151667dfe976ea29d3402b09ccccc1e319028514cdb2cba2b507235d61")
# Sys.getenv("FULCRUM_TOKEN")


# source .r file with my NEON_TOKEN
# source("my_neon_token.R") # OPTIONAL - load NEON token
# See: https://www.neonscience.org/neon-api-tokens-tutorial

# Macroinvert dpid
inv_dpid <- 'DP1.20120.001'

# list of sites
my_site_list <- c('CUPE','GUIL')

# get all tables for these sites from the API -- takes < 1 minute
all_tabs_inv <- loadByProduct(
  dpID = inv_dpid ,
  site = my_site_list, 
  startdate="2016-01", enddate="2024-04",
  package= 'basic', check.size=F, release = 'current')
  #token = NEON_TOKEN, #Uncomment to use your token
# what tables do you get with macroinvertebrate 
# data product
names(all_tabs_inv) ## [1] "categoricalCodes_20120" "inv_fieldData"          "inv_persample"  "inv_taxonomyProcessed"  "issueLog_20120"     
## [6] "readme_20120"           "validation_20120"       "variables_20120"



# extract items from list and put in R env. 
list2env(all_tabs_inv, .GlobalEnv)
{
## <environment: R_GlobalEnv>

# readme has the same informaiton as what you 
# will find on the landing page on the data portal

# The variables file describes each field in 
# the returned data tables
View(variables_20120)

# The validation file provides the rules that 
# constrain data upon ingest into the NEON database:
View(validation_20120)

# the categoricalCodes file provides controlled 
# lists used in the data
View(categoricalCodes_20120)
}

# It is good to check for duplicate records. This had occurred in the past in 
# data published in the inv_fieldData table in 2021. Those duplicates were 
# fixed in the 2022 data release. 
# Here we use sampleID as primary key and if we find duplicate records, we
# keep the first uid associated with any sampleID that has multiple uids

de_duped_uids <- inv_fieldData %>% 
  
  # remove records where no sample was collected
  filter(!is.na(sampleID)) %>%  
  group_by(sampleID) %>%
  summarise(n_recs = length(uid),
            n_unique_uids = length(unique(uid)),
            uid_to_keep = dplyr::first(uid)) 

# Are there any records that have more than one unique uid?
max_dups <- max(de_duped_uids$n_unique_uids %>% unique())


# filter data using de-duped uids if they exist

if(max_dups > 1){
  inv_fieldData <- inv_fieldData %>%
    dplyr::filter(uid %in% de_duped_uids$uid_to_keep)
}


# extract year from date, add it as a new column 
inv_fieldData <- inv_fieldData %>%
  mutate(
    year = collectDate %>% 
      lubridate::as_date() %>% 
      lubridate::year())

str(inv_fieldData)


# extract location data into a separate table
table_location <- inv_fieldData %>%
  
  # keep only the columns listed below
  select(siteID, 
         domainID,
         namedLocation, 
         decimalLatitude, 
         decimalLongitude, 
         elevation) %>%
  
  # keep rows with unique combinations of values, 
  # i.e., no duplicate records
  distinct()




# create a taxon table, which describes each 
# taxonID that appears in the data set
# start with inv_taxonomyProcessed
table_taxon <- inv_taxonomyProcessed %>%
  
  # keep only the coluns listed below
  select(acceptedTaxonID, taxonRank, scientificName,
         order, family, genus, 
         identificationQualifier,
         identificationReferences) %>%
  
  # remove rows with duplicate information
  distinct()



# taxon table information for all taxa in 
# our database can be downloaded here:
# takes 1-2 minutes
# full_taxon_table_from_api <- neonUtilities::getTaxonTable("MACROINVERTEBRATE", token = NEON_TOKEN)




# Make the observation table.
# start with inv_taxonomyProcessed

# check for repeated taxa within a sampleID that need to be added together
inv_taxonomyProcessed_summed <- inv_taxonomyProcessed %>% 
  select(sampleID,
         acceptedTaxonID,
         individualCount,
         estimatedTotalCount) %>%
  group_by(sampleID, acceptedTaxonID) %>%
  summarize(
    across(c(individualCount, estimatedTotalCount), ~sum(.x, na.rm = TRUE)))




# join summed taxon counts back with sample and field data
table_observation <- inv_taxonomyProcessed_summed %>%
  
  # Join relevant sample info back in by sampleID
  left_join(inv_taxonomyProcessed %>% 
              select(sampleID,
                     domainID,
                     siteID,
                     namedLocation,
                     collectDate,
                     acceptedTaxonID,
                     order, family, genus, 
                     scientificName,
                     taxonRank) %>%
              distinct()) %>%
  
  # Join the columns selected above with two 
  # columns from inv_fieldData (the two columns 
  # are sampleID and benthicArea)
  left_join(inv_fieldData %>% 
              select(sampleID, eventID, year, 
                     habitatType, samplerType,
                     benthicArea )) %>%
  
  # some new columns called 'variable_name', 
  # 'value', and 'unit', and assign values for 
  # all rows in the table.
  # variable_name and unit are both assigned the 
  # same text strint for all rows. 
  mutate(inv_dens = estimatedTotalCount / benthicArea,
         inv_dens_unit = 'count per square meter')





# check for duplicate records, should return a table with 0 rows
table_observation %>% 
  group_by(sampleID, acceptedTaxonID) %>% 
  summarize(n_obs = length(sampleID)) %>%
  filter(n_obs > 1)

## # A tibble: 0 x 3
## # Groups:   sampleID [0]
## # ... with 3 variables: sampleID <chr>, acceptedTaxonID <chr>, n_obs <int>

# extract sample info
table_sample_info <- table_observation %>%
  select(sampleID, domainID, siteID, namedLocation, 
         collectDate, eventID, year, 
         habitatType, samplerType, benthicArea, 
         inv_dens_unit) %>%
  distinct()




# remove singletons and doubletons
# create an occurrence summary table
taxa_occurrence_summary <- table_observation %>%
  select(sampleID, acceptedTaxonID) %>%
  distinct() %>%
  group_by(acceptedTaxonID) %>%
  summarize(occurrences = n())


# filter out taxa that are only observed 1 or 2 times
taxa_list_cleaned <- taxa_occurrence_summary %>%
  filter(occurrences > 2)



print(table_observation)

# filter observation table based on taxon list above
table_observation_cleaned <- table_observation %>%
  filter(acceptedTaxonID %in%
           taxa_list_cleaned$acceptedTaxonID,
         !sampleID %in% c("MAYF.20190729.CORE.1",
                          "MAYF.20200713.CORE.1",
                          "MAYF.20210721.CORE.1",
                          "POSE.20160718.HESS.1")) 
#this is an outlier sampleID

# some summary data
sampling_effort_summary <- table_sample_info %>%
  
  # group by siteID, year
  group_by(siteID, year, samplerType) %>%
  
  # count samples and habitat types within each event
  summarise(
    event_count = eventID %>% unique() %>% length(),
    sample_count = sampleID %>% unique() %>% length(),
    habitat_count = habitatType %>% 
      unique() %>% length())

# check out the summary table
sampling_effort_summary %>% as.data.frame() %>% 
  head() %>% print()

table_obs_year <-table_observation_cleaned %>% 
  group_by( siteID, taxonRank, year, season) %>%
  summarize(
    n_taxa = acceptedTaxonID %>% 
      unique() %>% length())

ggplot(table_obs_year) +                     ####Good graph need more aesthetics, size and names etc
  geom_bar(aes(x= n_taxa, y= taxonRank, fill = as.factor(year)), 
          position = "stack", stat = "identity") +
  facet_wrap(season~siteID, nrow= 3, scale ="free_x")


# number taxa by rank by site
table_observation_cleaned %>% 
  group_by( siteID, taxonRank) %>%
  summarize(
    n_taxa = acceptedTaxonID %>% 
      unique() %>% length()) %>%
  ggplot(aes(n_taxa, taxonRank)) +
  facet_wrap(~ siteID) +
  geom_col()

# library(scales)
# sum densities by order for each sampleID
table_observation_by_order <- 
  table_observation_cleaned %>% 
  filter(!is.na(order)) %>%
  group_by(siteID, year, 
           eventID, sampleID, habitatType, order) %>%
  summarize(order_dens = sum(inv_dens, na.rm = TRUE))


# rank occurrence by order
table_observation_by_order %>% head()

# stacked rank occurrence plot
table_observation_by_order %>%
  group_by(order, siteID) %>%
  summarize(
    occurrence = (order_dens > 0) %>% sum()) %>%
  ggplot(aes(
    x = reorder(order, -occurrence), 
    y = occurrence,
    color = siteID,
    fill = siteID)) +
  geom_col() +
  theme(axis.text.x = 
          element_text(angle = 45, hjust = 1))

#stacked rank occurance by year plot
table_observation_by_order %>%
  group_by(order, siteID, year) %>%
  summarize(
    occurrence = (order_dens > 0) %>% sum()) %>%
  ggplot(aes(
    x = reorder(order, -occurrence), 
    y = occurrence,
    color = siteID,
    fill = siteID)) +
  geom_col() +
  theme(axis.text.x = 
          element_text(angle = 45, hjust = 1))+
  facet_wrap(~year,  scales = "free_y")

# faceted densities plot
table_observation_by_order %>%
  ggplot(aes(
    x = reorder(order, -order_dens), 
    y = log10(order_dens),
    color = siteID,
    fill = siteID)) +
  geom_boxplot(alpha = .5) +
  facet_grid(siteID ~ .) +
  theme(axis.text.x = 
          element_text(angle = 45, hjust = 1))


####
# select only site by species density info and remove duplicate records
table_sample_by_taxon_density_long <- table_observation_cleaned %>%
  select(sampleID, acceptedTaxonID, inv_dens) %>%
  distinct() %>%
  filter(!is.na(inv_dens))

#table_sample_by_taxon_density_long %>% nrow()
#table_sample_by_taxon_density_long %>% distinct() %>% nrow()



# pivot to wide format, sum multiple counts per sampleID
table_sample_by_taxon_density_wide <- table_sample_by_taxon_density_long %>%
  tidyr::pivot_wider(id_cols = sampleID, 
                     names_from = acceptedTaxonID,
                     values_from = inv_dens,
                     values_fill = list(inv_dens = 0),
                     values_fn = list(inv_dens = sum)) %>%
  column_to_rownames(var = "sampleID") 

# check col and row sums -- mins should all be > 0
colSums(table_sample_by_taxon_density_wide) %>% min()
rowSums(table_sample_by_taxon_density_wide) %>% min()

#gamma is regional biodiversity
# alpha is local biodiversity (e.g., the mean diversity at a patch)  ##Alpha diversity is average local richness.
# and beta diversity is a measure of among-patch variability in community composition.
#beta = gamma / alpha

# Here we use vegan::renyi to calculate Hill numbers
# If hill = FALSE, the function returns an entropy
# If hill = TRUE, the function returns the exponentiated
# entropy. In other words:
# exp(renyi entropy) = Hill number = "species equivalent"

# Note that for this function, the "scales" argument 
# determines the order of q used in the calculation

table_sample_by_taxon_density_wide %>%
  vegan::renyi(scales = 0, hill = TRUE) %>%
  mean()

# even distribution, orders q = 0 and q = 1 for 10 taxa
vegan::renyi(
  c(spp.a = 10, spp.b = 10, spp.c = 10, 
    spp.d = 10, spp.e = 10, spp.f = 10, 
    spp.g = 10, spp.h = 10, spp.i = 10, 
    spp.j = 10),
  hill = TRUE,
  scales = c(0, 1))

# uneven distribution, orders q = 0 and q = 1 for 10 taxa
vegan::renyi(
  c(spp.a = 90, spp.b = 2, spp.c = 1, 
    spp.d = 1, spp.e = 1, spp.f = 1, 
    spp.g = 1, spp.h = 1, spp.i = 1, 
    spp.j = 1),
  hill = TRUE,
  scales = c(0, 1)) 

##Comparing orders of q of NEON data
# Nest data by siteID
data_nested_by_siteID <- table_sample_by_taxon_density_wide %>%
  tibble::rownames_to_column("sampleID") %>%
  left_join(table_sample_info %>% 
              select(sampleID, siteID)) %>%
  tibble::column_to_rownames("sampleID") %>%
  nest(data = -siteID)

data_nested_by_siteID$data[[1]] %>%
  vegan::renyi(scales = 0, hill = TRUE) %>%
  mean()

# apply the calculation by site for alpha diversity
# for each order of q
#Order q = 0 alpha diversity calculated for our dataset returns a mean local richness (i.e., species counts) 
#Order q = 1 alpha diversity returns mean number of "species equivalents" per sample in the data set.

data_nested_by_siteID %>% mutate(
  alpha_q0 = purrr::map_dbl(
    .x = data,
    .f = ~ vegan::renyi(x = .,
                        hill = TRUE, 
                        scales = 0) %>% mean()),
  alpha_q1 = purrr::map_dbl(
    .x = data,
    .f = ~ vegan::renyi(x = .,
                        hill = TRUE, 
                        scales = 1) %>% mean()),
  alpha_q2 = purrr::map_dbl(
    .x = data,
    .f = ~ vegan::renyi(x = .,
                        hill = TRUE, 
                        scales = 2) %>% mean())
)

# To calculate gamma diversity at the site scale,
# calculate the column means and then calculate 
# the renyi entropy and Hill number
# Here we are only calcuating order 
# q = 0 gamma diversity
data_nested_by_siteID %>% mutate(
  gamma_q0 = purrr::map_dbl(
    .x = data,
    .f = ~ vegan::renyi(x = colMeans(.),
                        hill = TRUE, 
                        scales = 0)))

# Now calculate alpha, beta, and gamma using orders 0 and 1 
# for each siteID
diversity_partitioning_results <- 
  data_nested_by_siteID %>% 
  mutate(
    n_samples = purrr::map_int(data, ~ nrow(.)),
    alpha_q0 = purrr::map_dbl(
      .x = data,
      .f = ~ vegan::renyi(x = .,
                          hill = TRUE, 
                          scales = 0) %>% mean()),
    alpha_q1 = purrr::map_dbl(
      .x = data,
      .f = ~ vegan::renyi(x = .,
                          hill = TRUE, 
                          scales = 1) %>% mean()),
    gamma_q0 = purrr::map_dbl(
      .x = data,
      .f = ~ vegan::renyi(x = colMeans(.),
                          hill = TRUE, 
                          scales = 0)),
    gamma_q1 = purrr::map_dbl(
      .x = data,
      .f = ~ vegan::renyi(x = colMeans(.),
                          hill = TRUE, 
                          scales = 1)),
    beta_q0 = gamma_q0 / alpha_q0,
    beta_q1 = gamma_q1 / alpha_q1)


diversity_partitioning_results %>% 
  select(-data) %>% as.data.frame() %>% print()

###NMDS is the Nonmetric Multidimensional Scaling to ordinate samples
# create ordination using NMDS
my_nmds_result <- table_sample_by_taxon_density_wide %>% vegan::metaMDS()

# plot stress
my_nmds_result$stress
p1 <- vegan::ordiplot(my_nmds_result)
vegan::ordilabel(p1, "species")

# merge NMDS scores with sampleID information for plotting
nmds_scores <- my_nmds_result %>% 
  vegan::scores() %>%
  .[["sites"]] %>%
  as.data.frame() %>%
  tibble::rownames_to_column("sampleID") %>%
  left_join(table_sample_info)

# # How I determined the outlier(s)
nmds_scores %>% arrange(desc(NMDS1)) %>% head()
nmds_scores %>% arrange(desc(NMDS1)) %>% tail()

# Plot samples in community composition space by year
nmds_scores %>%
  ggplot(aes(NMDS1, NMDS2, color = siteID, 
             shape = samplerType)) +
  geom_point() +
  facet_wrap(~ as.factor(year))

# Plot samples in community composition space
# facet by siteID and habitat type
# color by year
nmds_scores %>%
  ggplot(aes(NMDS1, NMDS2, color = as.factor(year), 
             shape = samplerType)) +
  geom_point() +
  facet_grid(habitatType ~ siteID, scales = "free")

##Maria addition
# color by year and season
nmds_scores %>%
  ggplot(aes(NMDS1, NMDS2, color = as.factor(year) 
             )) +
  geom_point() +
  facet_grid(season ~ siteID, scales = "free")

