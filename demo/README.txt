Setup a demo OAI server
-=-=-=-=-=-=-=-=-=-=-=-


Setup an ElasticSearch server
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
* Download ElasticSearch from https://www.elastic.co/downloads/elasticsearch
* Unzip the distribution
* Start an elasticsearch instance: 
   
   $ cd elasticsearch-X.Y.Z && bin/elasticsearch

Setup the Catmandu environment
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
* Install Catmandu::Store::ElasticSearch if not already available:

   $ cpanm Catmandu::Store::ElasticSearch

* The demo/catmandu.yml file incontains connection parameters
  to the elasticsearch instance:

   store:
    oai:
      package: ElasticSearch
      options:
         index_name: oai

   # Check if the server is running, this command shouldn't give
   # and error message
   $ catmandu export oai

   # Delete all the data from the oai store
   $ catmandu delete oai

   # Import some demo data
      # Choose to import some data from an online service
      $ catmandu import OAI --url http://pub.uni-bielefeld.de/oai --metadataPrefix oai_dc --from 2015-05-01 --handler oai_dc to oai

      # or

      # From a local dump
      $ catmandu import JSON to oai < demo.json

   # Check if we have data stored
   $ catmandu export oai

Setup the OAI Dancer environment
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
* The demo/config.yml file contains all the connection parameters
  to the elasticsearch instance and the basic parameters required for OAI

* The demo/demo.tt file defines how database records from the elasticsearch database 
  need to be translated into oai_dc records

* The demo/demo.pl file contains the Dancer application.
 
Start the Dancer application
-=-=-=-=-=-=-=-=-=-=-=-=-=-= 
* Make sure the elasticsearch server is up and running (see the top of this document)
* Start dancer:

  $ cd demo
  $ perl ./demo.pl

* An OAI server is now running on port 3000. 

* Test queries:

  $ curl "http://localhost:3000/oai?verb=Identify"
  $ curl "http://localhost:3000/oai?verb=ListSets"
  $ curl "http://localhost:3000/oai?verb=ListMetadataFormats"
  $ curl "http://localhost:3000/oai?verb=ListIdentifiers&metadataPrefix=oai_dc"
  $ curl "http://localhost:3000/oai?verb=ListRecords&metadataPrefix=oai_dc"
  $ curl "http://localhost:3000/oai?verb=GetRecord&identifier=oai:oai.service.com:oai:pub.uni-bielefeld.de:1857750&metadataPrefix=oai_dc"
