# NAME

Dancer::Plugin::Catmandu::OAI - OAI-PMH provider backed by a searchable Catmandu::Store

# VERSION

Version 0.0304

# SYNOPSIS

    use Dancer;
    use Dancer::Plugin::Catmandu::SRU;

    oai_provider '/oai';



# CONFIGURATION

    plugins:
        'Catmandu::OAI':
            store: oai
            bag: publication
            datestamp_field: date_updated
            repositoryName: "My OAI Service Provider" 
            uri_base: "http://oai.service.com/oai"
            adminEmail: me@example.com
            earliestDatestamp: "1970-01-01T00:00:01Z"
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
                    template: views/oai_dc.tt
                    filter: 'status exact public'
                    fix:
                      - publication_to_dc()
                -
                    metadataPrefix: mods
                    schema: "http://www.loc.gov/standards/mods/v3/mods-3-0.xsd"
                    metadataNamespace: "http://www.loc.gov/mods/v3"
                    template: views/mods.tt
                    filter: 'submissionstatus exact public'
                    fix:
                      - publication_to_mods()
            sets:
                - 
                    setSpec: openaccess
                    setName: Open Access
                    cql: 'oa=1'
                -
                    setSpec: journal_article
                    setName: Journal article
                    cql: 'documenttype exact journal_article'
                -
                    setSpec: book
                    setName: Book
                    cql: 'documenttype exact book'

# SEE ALSO

[Dancer::Plugin::Catmandu::SRU](https://metacpan.org/pod/Dancer::Plugin::Catmandu::SRU), [Catmandu](https://metacpan.org/pod/Catmandu), [Catmandu::Store](https://metacpan.org/pod/Catmandu::Store)

# AUTHOR

Nicolas Steenlant, `<nicolas.steenlant at ugent.be>`

# CONTRIBUTORS

Nicolas Franck, `<nicolas.franck at ugent.be>`

Vitali Peil, `<vitali.peil at uni-bielefeld.de>`

# LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
