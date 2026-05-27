# SPDX-FileCopyrightText: Contributors to PyPSA-Eur <https://github.com/pypsa/pypsa-eur>
#
# SPDX-License-Identifier: MIT
"""
Build industrial energy demand per model region.

Description
-------
This rule aggregates the energy demand of the industrial sectors per model region.
For each bus, the following carriers are considered:
- electricity
- coal
- coke
- solid biomass
- methane
- hydrogen
- low-temperature heat
- naphtha
- ammonia
- process emission
- process emission from feedstock

which can later be used as values for the industry load.
"""

import logging

import pandas as pd

from scripts._helpers import configure_logging, set_scenario_config

logger = logging.getLogger(__name__)

if __name__ == "__main__":
    if "snakemake" not in globals():
        from scripts._helpers import mock_snakemake

        snakemake = mock_snakemake(
            "build_industrial_energy_demand_per_node",
            clusters=48,
            planning_horizons=2030,
        )
    configure_logging(snakemake)
    set_scenario_config(snakemake)

    # import ratios
    fn = snakemake.input.industry_sector_ratios
    sector_ratios = pd.read_csv(fn, header=[0, 1], index_col=0)

    # material demand per node and industry (Mton/a)
    fn = snakemake.input.industrial_production_per_node
    nodal_production = pd.read_csv(fn, index_col=0) / 1e3

    # energy demand today to get current electricity
    fn = snakemake.input.industrial_energy_demand_per_node_today
    nodal_today = pd.read_csv(fn, index_col=0)

    nodal_sector_ratios = pd.concat(
        {node: sector_ratios[node[:2]] for node in nodal_production.index}, axis=1
    )

    nodal_production_stacked = nodal_production.stack()
    nodal_production_stacked.index.names = [None, None]

    # final energy consumption per node and industry (TWh/a)
    nodal_df = (
        (nodal_sector_ratios.multiply(nodal_production_stacked))
        .T.groupby(level=0)
        .sum()
    )

    rename_sectors = {
        "elec": "electricity",
        "biomass": "solid biomass",
        "heat": "low-temperature heat",
    }
    nodal_df.rename(columns=rename_sectors, inplace=True)

    nodal_df["current electricity"] = nodal_today["electricity"]

    nodal_df.index.name = "TWh/a (MtCO2/a)"
    countrries = snakemake.config['countries']
    config=snakemake.config
    def clever_industry_data():
        fn = snakemake.input.clever_industry
        df= pd.read_csv(fn ,index_col=0)
        return df
    clever_Industry = clever_industry_data() 
       
    for country in countrries:
     if config["run"]["name"] == "suff" or "sensitivity_analysis" in config["run"]["name"]: 
        country_energy = nodal_df[nodal_df.index.str.startswith(country)]
        nodal_df.loc[country_energy.index, 'ammonia'] = clever_Industry.loc[country, 'Total Final Energy Consumption of the ammonia industry']
        nodal_df.loc[country_energy.index, 'electricity'] = clever_Industry.loc[country, 'Total Final electricity consumption in industry']
        nodal_df.loc[country_energy.index, 'coal'] = clever_Industry.loc[country, 'Total Final energy consumption from solid fossil fuels (coal ...) in industry']
        nodal_df.loc[country_energy.index, 'solid biomass'] = clever_Industry.loc[country, 'Total Final energy consumption from solid biomass in industry']
        nodal_df.loc[country_energy.index, 'methane'] = clever_Industry.loc[country, 'Total Final energy consumption from gas grid / gas consumed locally in industry']
        nodal_df.loc[country_energy.index, 'low-temperature heat'] = clever_Industry.loc[country, 'Total Final heat consumption in industry']
        nodal_df.loc[country_energy.index, 'hydrogen'] = clever_Industry.loc[country, 'Total Final hydrogen consumption in industry'] + clever_Industry.loc[country, 'Non-energy consumption of hydrogen for the feedstock production'].sum()
        nodal_df.loc[country_energy.index, 'naphtha'] = clever_Industry.loc[country, 'Non-energy consumption of oil for the feedstock production'] + clever_Industry.loc[country, 'Total Final oil consumption in industry'].sum()
     else:
      nodal_df = nodal_df
    
    if config["run"]["name"] == "ref":
      nodal_df.loc['BE', 'naphtha']  =  84.4

    fn = snakemake.output.industrial_energy_demand_per_node
    nodal_df.to_csv(fn, float_format="%.2f")
