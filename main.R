# install.packages("bigrquery")
library("bigrquery")
library("geobr")
library("ggplot2")
library(maps)
library(dplyr)
library(sf)
library(plotly)
library(sfheaders)
library(stringr)

project_id <- "cloud-learning-doing"

sql <- "SELECT * FROM estban.estban_agencias_geolocalizadas WHERE data_base = '2010-12-01'"

# Download and write shapefiles
sp_code_tract <- geobr::read_census_tract(35)
regiao_metropolitana_sp <- geobr::read_meso_region(3515)


sf::write_sf(sp_code_tract, "data/sp_code_tract/sp_code_tract.shp")
sf::write_sf(regiao_metropolitana_sp, "data/regiao_metropolitana_sp/regiao_metropolitana_sp.shp")

# Load shapefiles locally
sp_code_tract <- sf::st_read("data/sp_code_tract/sp_code_tract.shp")
rm_sp <- sf::st_read("data/regiao_metropolitana_sp/regiao_metropolitana_sp.shp")

rm_sp_code_tract <- sp_code_tract |> filter(code_mn %in% mun_rm_sp)

# Data from banks
agencias_2010 <- bq_project_query(project_id, sql)

agencias_2010 <- bq_table_download(agencias_2010)

# Filter by polygon
agencias_rm_sp <- agencias_2010 |>
  dplyr::filter(!is.na(lat) & !is.na(lng)) |>
  sf::st_as_sf(coords = c("lng", "lat"), crs = 4674) |>
  sf::st_filter(rm_sp)

rm_sp_code_tract <- sf::st_join(sp_code_tract, rm_sp)

renda_sp <- read.csv("data/DomicilioRenda_SP1.csv", sep = ";") |>
  dplyr::mutate(code_district = as.character(Cod_setor)) |>
  dplyr::filter(V002 != "X")

renda_grande_sp <- read.csv("data/DomicilioRenda_SP2.csv", sep = ";") |>
  dplyr::mutate(code_district = as.character(Cod_setor)) |>
  dplyr::filter(V002 != "X")

renda_rm_sp <- union_all(renda_sp, renda_grande_sp) |>
  mutate(Cod_setor = as.character(Cod_setor))

rm_sp_code_tract <- rm_sp_code_tract |>
  left_join(renda_rm_sp, by = c("cd_trct" = "Cod_setor"))


rm_sp_code_tract$renda_nominal <- as.numeric(rm_sp_code_tract$V002) + as.numeric(rm_sp_code_tract$V003) + as.numeric(rm_sp_code_tract$V004)

agencias_por_setor_sp <- sf::st_join(rm_sp_code_tract, agencias_rm_sp)
sf::write_sf(agencias_por_setor_sp, "data/agencias_por_setor_sp/agencias_por_setor_sp.shp")


dados <- agencias_por_setor_sp |>
  group_by(cd_trct) |>
  summarize(
    depositos = sum(`401_402_404_411_412_413_414_415_416_417_418_419`),
    operacoes_de_credito = sum(`160`),
    financiamentos = sum(`162`),
    renda = sum(renda_nominal)
  )

dados$plf <- dados$depositos / dados$renda_nominal

dados$plb <- dados$depositos / dados$operacoes_de_credito

dados$txFin <- dados$financiamentos / dados$operacoes_de_credito

dados$credito_por_renda <- dados$operacoes_de_credito / dados$renda_nominal

dados$financiamentos_por_renda <- dados$financiamentos / dados$renda_nominal

dados2 <- sf::st_cast(dados, "MULTIPOLYGON")

grafico <- ggplot(dados2) +
  geom_sf(mapping = ggplot2::aes(fill = txFin)) +
  scale_fill_viridis_c()

grafico

inter <- plotly::ggplotly(grafico)
inter

write.csv(municipios_mesorregiao, "municipios_rm_sp.csv")
