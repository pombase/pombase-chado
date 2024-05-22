#!/usr/bin/env python3

# query GO for GO-CAM model IDs and process IDs

import requests
import sys

if len(sys.argv) != 2:
    print('needs 1 argument - the output file name')
    sys.exit(1)

test_mode = False

model_prefix = 'http://model.geneontology.org/'
term_prefix = 'http://purl.obolibrary.org/obo/'

url = 'https://rdf.geneontology.org/blazegraph/sparql'
data = {'format': 'json', 'query': '''
PREFIX gocam: <http://model.geneontology.org/>
PREFIX provided_by: <http://purl.org/pav/providedBy>
PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

SELECT distinct ?gocam ?processgoid WHERE {
  GRAPH ?gocam {
    ?gocam provided_by: "http://www.pombase.org"^^<http://www.w3.org/2001/XMLSchema#string> .
    ?part obo:BFO_0000050 ?process .
    ?process rdf:type ?processgoid
  }
  FILTER(strstarts(str(?processgoid), str(obo:)))
}
'''
}


try:
    response = requests.post(url, data=data)
    response.raise_for_status()
    rows = response.json()['results']['bindings']
except requests.exceptions.HTTPError as err:
    print('request failed: ' + err)
    sys.exit(1)


table = []

for row in rows:
    gocam_id = row['gocam']['value']
    if gocam_id.startswith(model_prefix):
        gocam_id = gocam_id[len(model_prefix):]
    else:
        print(f'parsing failed, gocam value doesn\'t begin with expected prefix: {gocam_id}')
        sys.exit(1)

    process_id = row['processgoid']['value']
    if process_id.startswith(term_prefix):
        process_id = process_id[len(term_prefix):]
        process_id = process_id.replace('_', ':')
    else:
        print(f'parsing failed, processgoid value doesn\'t begin with expected prefix: {process_id}')
        sys.exit(1)

    table.append([process_id, gocam_id])


with open(sys.argv[1], 'w') as writer:
    writer.write('# term ID to GO-CAM ID mapping\n')

    for row in table:
        writer.write(f"{row[0]}\t{row[1]}\n")


sys.exit(0)
