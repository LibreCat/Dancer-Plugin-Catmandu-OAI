# NAME

Dancer::Plugin::Catmandu::OAI - OAI-PMH provider backed by a searchable Catmandu::Store

# SYNOPSIS

    #!/usr/bin/env perl

    use Dancer;
    use Catmandu;
    use Dancer::Plugin::Catmandu::OAI;

    Catmandu->load;
    Catmandu->config;

    my $options = {};

    oai_provider '/oai' , %$options;

    dance;

# DESCRIPTION

[Dancer::Plugin::Catmandu::OAI](https://metacpan.org/pod/Dancer::Plugin::Catmandu::OAI) is a Dancer plugin to provide OAI-PMH services for [Catmandu::Store](https://metacpan.org/pod/Catmandu::Store)-s that support
CQL (such as [Catmandu::Store::ElasticSearch](https://metacpan.org/pod/Catmandu::Store::ElasticSearch)). Follow the installation steps below to setup your own OAI-PMH server.

# REQUIREMENTS

In the examples below an ElasticSearch 1.7.2 [https://www.elastic.co/downloads/past-releases/elasticsearch-1-7-2](https://www.elastic.co/downloads/past-releases/elasticsearch-1-7-2) server
will be used.

Follow the instructions below for a demonstration installation:

    $ cpanm Dancer Catmandu::OAI Catmandu::Store::ElasticSearch

    $ wget https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.7.2.zip
    $ unzip elasticsearch-1.7.2.zip
    $ cd elasticsearch-1.7.2
    $ bin/elasticsearch

# RECORDS

Records stored in the Catmandu::Store can be in any format. Preferably the format should be easy to convert into the
mandatory OAI-DC format. At a minimum each record contains an identifier '\_id' and a field containing a datestamp.

    $ cat sample.yml
    ---
    _id: oai:my.server.org:123456
    datestamp: 2016-05-17T13:37:18Z
    creator:
     - Musterman, Max
     - Jansen, Jan
     - Svenson, Sven
    title:
     - Test record
    ...

# CATMANDU CONFIGURATION

ElasticSearch requires a configuration file to map record fields to CQL terms. Below is a minimal configuration required to query
for identifiers and datastamps in the ElasticSearch collection:

    $ cat catmandu.yml
    ---
    store:
      oai:
        package: ElasticSearch
        options:
          index_name: oai
          bags:
            data:
              cql_mapping:
                default_index: basic
                indexes:
                  _id:
                    op:
                      'any': true
                      'all': true
                      '=': true
                      'exact': true
                    field: '_id'
                  datestamp:
                    op:
                      '=': true
                      '<': true
                      '<=': true
                      '>=': true
                      '>': true
                      'exact': true
                    field: 'datestamp'
          index_mappings:
            publication:
              properties:
                datestamp: {type: date, format: date_time_no_millis}

# IMPORT RECORDS

With the Catmandu configuration files in place records can be imported with the [catmandu](https://metacpan.org/pod/catmandu) command:

    # Drop the existing ElasticSearch 'oai' collection
    $ catmandu drop oai

    # Import the sample record
    $ catmandu import YAML to oai < sample.yml

    # Test if the records are available in the 'oai' collection
    $ catmandu export oai

# DANCER CONFIGURATION

The Dancer configuration file 'config.yml' contains basic information for the OAI-PMH plugin to work:

    * store - In which Catmandu::Store are the metadata records stored
    * bag - In which Catmandu::Bag are the records of this 'store' (use: 'data' as default)
    * datestamp_field - Which field in the record contains a datestamp ('datestamp' in our example above)
    * repositoryName - The name of the repository
    * uri_base - The full base url of the OAI controller. To be used when behind a proxy server. When not set, this module relies on the Dancer request to provide its full url. Use middleware like 'ReverseProxy' or 'Dancer::Middleware::Rebase' in that case.
    * adminEmail - An administrative email. Can be string or array of strings. This will be included in the Identify response.
    * compression - a compression encoding supported by the repository. Can be string or array of strings. This will be included in the Identify response.
    * description - XML container that describes your repository. Can be string or array of strings. This will be included in the Identify response. Note that this module will try to validate the XML data.
    * earliestDatestamp - The earliest datestamp available in the dataset as YYYY-MM-DDTHH:MM:SSZ. This will be determined dynamically if no static value is given.
    * deletedRecord - The policy for deleted records. See also: L<https://www.openarchives.org/OAI/openarchivesprotocol.html#DeletedRecords>
    * repositoryIdentifier - A prefix to use in OAI-PMH identifiers
    * cql_filter -  A CQL query to find all records in the database that should be made available to OAI-PMH
    * limit - The maximum number of records to be returned in each OAI-PMH request
    * delimiter - Delimiters used in prefixing a record identifier with a repositoryIdentifier (use: ':' as default)
    * sampleIdentifier - A sample identifier
    * metadata_formats - An array of metadataFormats that are supported
        * metadataPrefix - A short string for the name of the format
        * schema - An URL to the XSD schema of this format
        * metadataNamespace - A XML namespace for this format
        * template - The path to a Template Toolkit file to transform your records into this format
        * fix - Optionally an array of one or more L<Catmandu::Fix>-es or Fix files
    * sets - Optional an array of OAI-PMH sets and the CQL query to retrieve records in this set from the Catmandu::Store
        * setSpec - A short string for the same of the set
        * setName - A longer description of the set
        * setDescription - an optional and repeatable container that may hold community-specific XML-encoded data about the set. Should be string or array of strings.
        * cql - The CQL command to find records in this set in the L<Catmandu::Store>
    * xsl_stylesheet - Optional path to an xsl stylesheet
    * template_options - An optional hash of configuration options that will be passed to L<Catmandu::Exporter::Template> or L<Template>.

Below is a sample minimal configuration for the 'sample.yml' demo above:

    $ cat config.yml
    charset: "UTF-8"
    plugins:
      'Catmandu::OAI':
        store: oai
        bag: data
        datestamp_field: datestamp
        repositoryName: "My OAI DataProvider"
        uri_base: "http://oai.service.com/oai"
        adminEmail: me@example.com
        earliestDatestamp: "1970-01-01T00:00:01Z"
        cql_filter: "datestamp>1970-01-01T00:00:01Z"
        deletedRecord: persistent
        repositoryIdentifier: oai.service.com
        limit: 200
        delimiter: ":"
        sampleIdentifier: "oai:oai.service.com:1585315"
        metadata_formats:
          -
            metadataPrefix: oai_dc
            schema: "http://www.openarchives.org/OAI/2.0/oai_dc.xsd"
            metadataNamespace: "http://www.openarchives.org/OAI/2.0/oai_dc/"
            template: oai_dc.tt

# METADATAPREFIX TEMPLATE

For each metadataPrefix a Template Toolkit file needs to exist which translate [Catmandu::Store](https://metacpan.org/pod/Catmandu::Store) records into XML records. At least
one Template Toolkit file should be made available to transform stored records into Dublin Core. The example below contains an example file to
transform 'sample.yml' type records into Dublin Core:

    $ cat oai_dc.tt
    <oai_dc:dc xmlns="http://www.openarchives.org/OAI/2.0/oai_dc/"
               xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/"
               xmlns:dc="http://purl.org/dc/elements/1.1/"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
               xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd">
    [%- FOREACH var IN ['title' 'creator' 'subject' 'description' 'publisher' 'contributor' 'date' 'type' 'format' 'identifier' 'source' 'language' 'relation' 'coverage' 'rights'] %]
        [%- FOREACH val IN $var %]
        <dc:[% var %]>[% val | html %]</dc:[% var %]>
        [%- END %]
    [%- END %]
    </oai_dc:dc>

# START DANCER

If all the required files are available, then a Dancer application can be started. See the 'demo' directory of this distribution for a complete example:

    $ ls
    app.pl  catmandu.yml  config.yml  oai_dc.tt
    $ cat app.pl
    #!/usr/bin/env perl

    use Dancer;
    use Catmandu;
    use Dancer::Plugin::Catmandu::OAI;

    Catmandu->load;
    Catmandu->config;

    my $options = {};

    oai_provider '/oai' , %$options;

    dance;

    # Start Dancer
    $ perl ./app.pl

    # Test queries:

    $ curl "http://localhost:3000/oai?verb=Identify"
    $ curl "http://localhost:3000/oai?verb=ListSets"
    $ curl "http://localhost:3000/oai?verb=ListMetadataFormats"
    $ curl "http://localhost:3000/oai?verb=ListIdentifiers&metadataPrefix=oai_dc"
    $ curl "http://localhost:3000/oai?verb=ListRecords&metadataPrefix=oai_dc"

# SEE ALSO

[Dancer](https://metacpan.org/pod/Dancer), [Catmandu](https://metacpan.org/pod/Catmandu), [Catmandu::Store](https://metacpan.org/pod/Catmandu::Store)

# AUTHOR

Nicolas Steenlant, `<nicolas.steenlant at ugent.be>`

# CONTRIBUTORS

Nicolas Franck, `<nicolas.franck at ugent.be>`

Vitali Peil, `<vitali.peil at uni-bielefeld.de>`

Patrick Hochstenbach, `<patric.hochstenbach at ugent.be>`

# LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
