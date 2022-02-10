# Conda package

This folder contains a conda recipe template to build the `hail` package for
the [`cpg` Anaconda channel](https://anaconda.org/cpg/hail).

The recipe is rendered and built in a GitHub CI workflow
[.github/workflows/build_package.yaml](.github/workflows/build_package.yaml), 
and pushes it to Anaconda on every push event to the `main` branch.

## Installation

Note that there is also a `hail` package in the
[`bioconda` channel](https://github.com/bioconda/bioconda-recipes/tree/master/recipes/hail)
synced with the [official PyPI release](https://pypi.org/project/hail). However, having
a separate conda package in the `cpg` channel allows us to build it against the codebase
in our fork.

When installing the package, list the `cpg` channel before `bioconda` to prioritize
the channel order:

```
conda create --name hail -c cpg -c bioconda -c conda-forge hail
conda activate hail
```

You can also install Hail into an existing environment.

Note that if you don't have `conda` installed, here are handy commands to do that:

```
if [[ "$OSTYPE" == "darwin"* ]]; then
    wget https://repo.continuum.io/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -O miniconda.sh
else
    wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
fi
bash miniconda.sh
```
