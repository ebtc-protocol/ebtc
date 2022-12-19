# Installing infrastructure and running simulation tests

## Installation:
From root directory create virtual env:
- `python3 -m venv venv`
- `source venv/bin/activate`

Install dependencies required to run simulation suite
- `pip install -r requirements.txt`

At this stage  you should be good to go

## Running simulations and observing results

Cd into test directory:
- `cd packages/contracts/tests`

Run simulation test:
- `brownie test -s`

Results will be stored in `simulation.csv file`

## Configuring depth of simulations:
One can configure depth of simulations by changing `n_sim` variable

Can be one of the following:
- `n_sim = day`
- `n_sim = month`
- `n_sim = year`

Please, note that in order to run full year simulation it would require around 7-8 hours of real time