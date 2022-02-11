#!/usr/bin/env python

"""
Render recipe:
- populate dependencies from the pip requirements
- set the package version,
- pin spark version.
"""
import sys

SPARK_VERSION = 'hail/env/SPARK_VERSION'
PIP_REQS = 'hail/python/requirements.txt'
META_TEMPLATE = 'conda/hail/meta-template.yaml'
META_RENDERED = 'conda/hail/meta.yaml'

if len(sys.argv) <= 1:
    raise ValueError(
        'Please, provide package version after as the first positional argument'
    )
package_version = sys.argv[1]

with open(SPARK_VERSION, 'r', encoding='utf-8') as file:
    spark_version = file.read()

dependencies = []
with open(PIP_REQS, 'r', encoding='utf-8') as f:
    for line in f:
        stripped = line.strip()
        if stripped.startswith('#') or len(stripped) == 0:
            continue
        pkg = stripped
        if pkg.startswith('pyspark'):
            # already in the template
            continue
        # Removing all >, >= and == version pins, that conda-build can't 
        # always reliably resolve:
        pkg = pkg.split('>')[0].strip()
        pkg = pkg.split('==')[0].strip()
        # conda uses dashes where pip uses underscores
        pkg = pkg.replace('_', '-')
        if pkg == 'avro':
            pkg = 'python-avro'
        dependencies.append(pkg)

with open(META_TEMPLATE) as inp, open(META_RENDERED, 'w') as out:
    for line in inp:
        if line.startswith('{other-requirements}'):
            for dep in dependencies:
                out.write(f'    - {dep}\n')
        else:
            # setting the package's version:
            line = line.replace('{version}', package_version)
            # adding the spark pin in the host section:
            line = line.replace('{pyspark-pin}', f'=={spark_version}')
            out.write(line)
