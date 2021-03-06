library(glmtools)
library(GLM3r)
library(rLakeAnalyzer)
library(tidyverse)
library(lubridate)

sim_folder <- getwd()
out_file <- file.path(sim_folder, "output","output.nc")
nml_file <- file.path(sim_folder, 'glm3_woAED.nml')
# set start and stop to 1985-01-01 to 2012-01-01
# original set as
#start = '2007-08-28 12:00:00'
#stop = '2018-12-31 12:00:00'

field_temp <- file.path(paste0(sim_folder, '/data/formatted-data/manual_buoy_temp.csv'))
field_stage <- file.path(paste0(sim_folder, '/data/field_stage.csv'))
field_obs <- read.csv(field_temp)
field_obs <- na.omit(field_obs)
field_obs$DateTime <- as.POSIXct(field_obs$DateTime)

ggplot(data = field_obs, aes(x = DateTime, y = Depth)) +
  geom_point(aes(color = Temp)) +
  scale_y_reverse()


# Run GLMr
GLM3r::run_glm(sim_folder, nml_file = 'glm3_woAED.nml', verbose = T)

temp_rmse <- compare_to_field(nc_file = out_file, 
                              field_file = field_temp,
                              metric = 'water.temperature', 
                              as_value = FALSE, 
                              precision= 'hours')
temp_rmse


# visualize change of water table over time
water_height <- get_surface_height(file = out_file)
ggplot(water_height, aes(DateTime, surface_height)) +
  geom_line() +
  ggtitle('Surface water level') +
  xlab(label = '') + ylab(label = 'Water level (m)') +
  theme_minimal()

plot_compare_stage(nc_file = out_file,
                   field_file = field_stage)

stage_obs <- read.csv(field_stage)
stage_obs$DateTime <- as.POSIXct(stage_obs$DateTime)
compare_stage <- left_join(water_height, stage_obs)
plot(stage_obs$DateTime, stage_obs$stage, ylim = c(0, 35), xlim = c(as.POSIXct('2007-01-01 00:00:00'), as.POSIXct('2014-01-01 00:00:00')))
points(water_height$DateTime, water_height$surface_height, type = 'l', col = 'red', lwd = 2)

# visualize ice formation over time
ice_thickness <- get_ice(file = out_file)
ggplot(ice_thickness, aes(DateTime, `ice(m)`)) +
  geom_line() +
  ggtitle('Ice') +
  xlab(label = '') + ylab(label = 'Ice thickness (m)') +
  theme_minimal()

# visualize change of surface water temp. over time
surface_temp <- get_var(file = out_file, 
                        var_name = 'temp',
                        reference = 'surface',
                        z_out = 2)
ggplot(surface_temp, aes(DateTime, temp_2)) +
  geom_line() +
  ggtitle('Surface water temperature') +
  xlab(label = '') + ylab(label = 'Temp. (deg C)') +
  theme_minimal()
plot_var_nc(out_file, var_name = 'temp')



# visualize change of bottom water temp. over time

bottom_temp <- get_var(file = out_file, 
                       var_name = 'temp',
                       reference = 'surface',
                       z_out = 10)
ggplot(bottom_temp, aes(DateTime, temp_10)) +
  geom_line(aes(color = 'red')) +
  geom_point(data = field_obs[field_obs$Depth==10,], aes(as.POSIXct(DateTime), Temp)) +
  ggtitle('Bottom water temperature') +
  xlab(label = '') + ylab(label = 'Temp. (deg C)') +
  theme_minimal()


temp_plot <- plot_var_compare(nc_file = out_file, 
                              field_file = field_temp, 
                              var_name = 'temp')
temp_plot

# depth specific plots
depths <- seq(0.5, 33, by = 0.5) #c(0.5, 1.0, 1.5, 2.0, 2.5, 
           #  3.0, 3.5, 4.5, 5.5, 
           #  6.5, 7.5, 8.5,  
           #  9.5,  10.5, 11.5, 13.5)

temp_depths <- get_var(file = out_file, 
                       var_name = 'temp',
                       reference = 'surface',
                       z_out = depths)
modtemp <- get_temp(out_file, reference="surface", z_out=depths) %>%
  pivot_longer(cols=starts_with("temp_"), names_to="Depth", names_prefix="temp_", values_to = "temp") %>%
  mutate(DateTime = as.POSIXct(strptime(DateTime, "%Y-%m-%d %H:%M:%S"))) %>% 
  rename(modtemp = temp) %>% 
  mutate(Depth = as.numeric(Depth))

#lets do depth by depth comparisons of the obs vs mod temps for each focal depth
watertemp<-left_join(modtemp, field_obs, by=c("DateTime","Depth")) %>%
  rename(obstemp = Temp) %>% 
  mutate(resid = modtemp - obstemp) %>% 
  mutate(yday = yday(DateTime)) %>% 
  filter(DateTime > as.POSIXct('2008-08-28'))

for(i in 1:length(unique(watertemp$Depth))){
  tempdf<-subset(watertemp, watertemp$Depth==depths[i])
  plot(tempdf$DateTime, tempdf$obstemp, col='red',
       ylab='temperature', xlab='time',
       main = paste0("Obs=Red,Mod=Black,Depth=",depths[i]),ylim=c(0,30))
  points(tempdf$DateTime, tempdf$obstemp, type = "l", col='red')
  points(tempdf$DateTime, tempdf$modtemp, type="l",col='black')
}


# residual plots!
p1 <- ggplot(data = watertemp, aes(x = yday, y = resid)) +
  geom_point(aes(color = factor(Depth))) #+
theme(legend.position = 'none')

p2 <- ggplot(data = watertemp, aes(x = resid, y = Depth)) +
  geom_point(aes(color = factor(Depth))) +
  scale_y_reverse() +
  theme(legend.position = 'none')

p3 <- ggplot(data = watertemp, aes(x = modtemp, y = obstemp)) +
  geom_point(aes(color = factor(Depth))) +
  theme(legend.position = 'none')

p4 <- ggplot(data = watertemp, aes(x = DateTime, y = modtemp)) +
  geom_point(aes(x = DateTime, y = obstemp, color = factor(Depth))) +
  geom_line(aes(color = factor(Depth))) +
  theme(legend.position = 'none')

p5 <- ggplot(data = watertemp, aes(x = resid)) +
  geom_histogram() +
  theme(legend.position = 'none')

p6 <- ggplot(data = watertemp, aes(x = modtemp, y = resid)) +
  geom_point(aes(color = factor(Depth))) +
  theme(legend.position = 'none')
p1
p2
p3
p4
p5
p6
library(patchwork)
p1 + p2/p3 + p4
all <- (p1 + p2 + p3)/(p4 + p5 + p6)

png('./output/diag_plots_16Jun21_1985-2018sim.png', height = 800, width = 650)
all + plot_annotation(
  title = "GLM run 2007-2018 (calibrated 2007-2011)"
)
dev.off()
