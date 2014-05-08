package Dancer::Plugin::Catmandu::OAI; # TODO hierarchical sets, setDescription

=head1 NAME

Dancer::Plugin::Catmandu::OAI - OAI-PMH provider backed by a searchable Catmandu::Store

=cut

our $VERSION = '0.0305';

use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Catmandu;
use Catmandu::Fix;
use Catmandu::Exporter::Template;
use Dancer::Plugin;
use Dancer qw(:syntax);
use DateTime;
use DateTime::Format::Strptime;
use Clone qw(clone);

my $DEFAULT_LIMIT = 100;

my $VERBS = {
    GetRecord => {
        valid    => {metadataPrefix => 1, identifier => 1},
        required => [qw(metadataPrefix identifier)],
    },
    Identify => {
        valid    => {},
        required => [],
    },
    ListIdentifiers => {
        valid    => {metadataPrefix => 1, from => 1, until => 1, set => 1, resumptionToken => 1},
        required => [qw(metadataPrefix)],
    },
    ListMetadataFormats => {
        valid    => {identifier => 1, resumptionToken => 1},
        required => [],
    },
    ListRecords => {
        valid    => {metadataPrefix => 1, from => 1, until => 1, set => 1, resumptionToken => 1},
        required => [qw(metadataPrefix)],
    },
    ListSets => {
        valid    => {resumptionToken => 1},
        required => [],
    },
};

sub parse_oai_datestamp {
    my ($date) = @_;
    my @d = $date =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
    DateTime->new(
        year      => $d[0],
        month     => $d[1],
        day       => $d[2],
        hour      => $d[3],
        minute    => $d[4],
        second    => $d[5],
        time_zone => 'UTC',
    );
}

sub render {
    my ($tmpl, $data) = @_;
    my $out = "";
    my $exporter = Catmandu::Exporter::Template->new(template => $tmpl, file => \$out);
    $exporter->add($data);
    $exporter->commit;
    $out;
}

sub oai_provider {
    my ($path, %opts) = @_;

    my $setting = clone(plugin_setting);

    $setting->{granularity} //= "YYYY-MM-DDThh:mm:ssZ";
    $setting->{get_record_cql_pattern} //= '_id exact "%s"';

    if ($setting->{filter}) {
        $setting->{cql_filter} = delete $setting->{filter};
    }

    $setting->{default_search_params} ||= {};

    my $datestamp_parser;
    if ($setting->{datestamp_pattern}) {
        $datestamp_parser = DateTime::Format::Strptime->new(
            pattern  => $setting->{datestamp_pattern},
            on_error => 'undef',
        );
    }

    my $format_datestamp = $datestamp_parser ? sub {
        $datestamp_parser->parse_datetime($_[0])->iso8601.'Z';
    } : sub {
        $_[0];
    };

    my $metadata_formats = do {
        my $list = $setting->{metadata_formats};
        my $hash = {};
        for my $format (@$list) {
            my $prefix = $format->{metadataPrefix};
            $format = {%$format};
            if (my $fix = $format->{fix}) {
                $format->{fix} = Catmandu::Fix->new(fixes => $fix);
            }
            $hash->{$prefix} = $format;
        }
        $hash;
    };

    my $sets = do {
        if (my $list = $setting->{sets}) {
            my $hash = {};
            for my $set (@$list) {
                my $key = $set->{setSpec};
                $hash->{$key} = $set;
            }
            $hash;
        } else {
            0;
        }
    };

    my $ns = "oai:$setting->{repositoryIdentifier}:";

    my $branding = "";
    if (my $icon = $setting->{collectionIcon}) {
        if (my $url = $icon->{url}) {
            $branding .= <<TT;
<description>
<branding xmlns="http://www.openarchives.org/OAI/2.0/branding/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/branding/ http://www.openarchives.org/OAI/2.0/branding.xsd">
<collectionIcon>
<url>$url</url>
TT
            for my $tag (qw(link title width height)) {
                my $val = $icon->{$tag} // next;
                $branding .= "<$tag>$val</$tag>\n";
            }

            $branding .= <<TT;
</collectionIcon>
</branding>
</description>
TT
        }
    }

    my $template_header = <<TT;
<?xml version="1.0" encoding="UTF-8"?>
<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
<responseDate>[% response_date %]</responseDate>
[%- IF params.resumptionToken %]
<request verb="[% params.verb %]" resumptionToken="[% params.resumptionToken %]">[% uri_base %]</request>
[%- ELSE %]
<request[% FOREACH param IN params %] [% param.key %]="[% param.value | xml %]"[% END %]>[% uri_base %]</request>
[%- END %]
TT

    my $template_footer = <<TT;
</OAI-PMH>
TT

    my $template_error = <<TT;
$template_header
[%- FOREACH error IN errors %]
<error code="[% error.0 %]">[% error.1 | xml %]</error>
[%- END %]
$template_footer
TT

    my $template_record_header = <<TT;
<header[% IF deleted %] status="deleted"[% END %]>
    <identifier>${ns}[% id %]</identifier>
    <datestamp>[% datestamp %]</datestamp>
    [%- FOREACH s IN setSpec %]
    <setSpec>[% s %]</setSpec>
    [%- END %]
</header>
TT

    my $template_get_record = <<TT;
$template_header
<GetRecord>
<record>
$template_record_header
[%- UNLESS deleted %]
<metadata>
[% metadata %]
</metadata>
[%- END %]
</record>
</GetRecord>
$template_footer
TT

    my $template_identify = <<TT;
$template_header
<Identify>
<repositoryName>$setting->{repositoryName}</repositoryName>
<baseURL>[% uri_base %]</baseURL>
<protocolVersion>2.0</protocolVersion>
<adminEmail>$setting->{adminEmail}</adminEmail>
<earliestDatestamp>$setting->{earliestDatestamp}</earliestDatestamp>
<deletedRecord>$setting->{deletedRecord}</deletedRecord>
<granularity>$setting->{granularity}</granularity>
<description>
    <oai-identifier xmlns="http://www.openarchives.org/OAI/2.0/oai-identifier"
                    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                    xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai-identifier http://www.openarchives.org/OAI/2.0/oai-identifier.xsd">
        <scheme>oai</scheme>
        <repositoryIdentifier>$setting->{repositoryIdentifier}</repositoryIdentifier>
        <delimiter>$setting->{delimiter}</delimiter>
        <sampleIdentifier>$setting->{sampleIdentifier}</sampleIdentifier>
    </oai-identifier>
</description>
$branding
</Identify>
$template_footer
TT

    my $template_list_identifiers = <<TT;
$template_header
<ListIdentifiers>
[%- FOREACH records %]
$template_record_header
[%- END %]
[%- IF token %]
<resumptionToken cursor="[% start %]" completeListSize="[% total %]">[% token %]</resumptionToken>
[%- ELSE %]
<resumptionToken cursor="[% start %]" completeListSize="[% total %]"/>
[%- END %]
</ListIdentifiers>
$template_footer
TT

    my $template_list_records = <<TT;
$template_header
<ListRecords>
[%- FOREACH records %]
<record>
$template_record_header
[%- UNLESS deleted %]
<metadata>
[% metadata %]
</metadata>
[%- END %]
</record>
[%- END %]
[%- IF token %]
<resumptionToken cursor="[% start %]" completeListSize="[% total %]">[% token %]</resumptionToken>
[%- ELSE %]
<resumptionToken cursor="[% start %]" completeListSize="[% total %]"/>
[%- END %]
</ListRecords>
$template_footer
TT

    my $template_list_metadata_formats = "";
    $template_list_metadata_formats .= <<TT;
$template_header
<ListMetadataFormats>
TT
    for my $format (values %$metadata_formats) {
        $template_list_metadata_formats .= <<TT;
<metadataFormat>
    <metadataPrefix>$format->{metadataPrefix}</metadataPrefix>
    <schema>$format->{schema}</schema>
    <metadataNamespace>$format->{metadataNamespace}</metadataNamespace>
</metadataFormat>
TT
    }
    $template_list_metadata_formats .= <<TT;
</ListMetadataFormats>
$template_footer
TT

    my $template_list_sets = <<TT;
$template_header
<ListSets>
TT
    for my $set (values %$sets) {
        $template_list_sets .= <<TT;
<set>
    <setSpec>$set->{setSpec}</setSpec>
    <setName>$set->{setName}</setName>
</set>
TT
    }
    $template_list_sets .= <<TT;
</ListSets>
$template_footer
TT

    my $fix = $opts{fix} || $setting->{fix};
    my $sub_deleted = $opts{deleted} || sub { 0 };
    my $sub_set_specs_for = $opts{set_specs_for} || sub { [] };

    my $bag = Catmandu->store($opts{store} || $setting->{store})->bag($opts{bag} || $setting->{bag});

    any ['get', 'post'] => $path => sub {
        my $uri_base = $setting->{uri_base} // request->uri_base;
        my $response_date = DateTime->now->iso8601.'Z';
        my $params = request->is_get ? params('query') : params('body');
        my $errors = [];
        my $format;
        my $set;
        my $verb = $params->{verb};
        my $vars = {
            uri_base => $uri_base,
            request_uri => $uri_base . $path,
            response_date => $response_date,
            errors => $errors,
        };

        if ($verb and my $spec = $VERBS->{$verb}) {
            my $valid = $spec->{valid};
            my $required = $spec->{required};

            if ($valid->{resumptionToken} and exists $params->{resumptionToken}) {
                if (keys(%$params) > 2) {
                    push @$errors, [badArgument => "resumptionToken cannot be combined with other parameters"];
                }
            } else {
                for my $key (keys %$params) {
                    next if $key eq 'verb';
                    unless ($valid->{$key}) {
                        push @$errors, [badArgument => "parameter $key is illegal"];
                    }
                }
                for my $key (@$required) {
                    unless (exists $params->{$key}) {
                        push @$errors, [badArgument => "parameter $key is missing"];
                    }
                }
            }
        } else {
            push @$errors, [badVerb => "illegal OAI verb"];
        }

        if (@$errors) {
            return render(\$template_error, $vars);
        }

        $vars->{params} = $params;

        if ($params->{resumptionToken}) {
            unless (is_string($params->{resumptionToken})) {
                push @$errors, [badResumptionToken => "resumptionToken is not in the correct format"];
            }

            if ($verb eq 'ListSets') {
                push @$errors, [badResumptionToken => "resumptionToken isn't necessary"];
            } else {
                my @parts = split '!', $params->{resumptionToken};

                unless (@parts == 5) {
                    push @$errors, [badResumptionToken => "resumptionToken is not in the correct format"];
                }

                $params->{set}            = $parts[0];
                $params->{from}           = $parts[1];
                $params->{until}          = $parts[2];
                $params->{metadataPrefix} = $parts[3];
                $vars->{start}            = $parts[4];
            }
        }

        if ($params->{set}) {
            unless ($sets) {
                push @$errors, [noSetHierarchy => "sets are not supported"];
            }
            unless ($set = $sets->{$params->{set}}) {
                push @$errors, [badArgument => "set does not exist"];
            }
        }

        if (my $prefix = $params->{metadataPrefix}) {
            unless ($format = $metadata_formats->{$prefix}) {
                push @$errors, [cannotDisseminateFormat => "metadataPrefix $prefix is not supported"];
            }
        }

        if (@$errors) {
            return render(\$template_error, $vars);
        }

        content_type 'xml';

        if ($verb eq 'GetRecord') {
            my $id = $params->{identifier};
            $id =~ s/^$ns//;

            my $rec = $bag->search(
                %{ $setting->{default_search_params} },
                cql_query => sprintf($setting->{get_record_cql_pattern}, $id),
                start     => 0,
                limit     => 1,

            )->first;

            if (defined $rec) {
                if ($fix) {
                    $rec = Catmandu->fixer($fix)->fix($rec);
                }

                $vars->{id} = $id;
                $vars->{datestamp} = $format_datestamp->($rec->{$setting->{datestamp_field}});
                $vars->{deleted} = $sub_deleted->($rec);
                $vars->{setSpec} = $sub_set_specs_for->($rec);
                my $metadata = "";
                my $exporter = Catmandu::Exporter::Template->new(
                    template => $format->{template},
                    file => \$metadata,
                    fix => $format->{fix},
                );
                $exporter->add($rec);
                $exporter->commit;
                $vars->{metadata} = $metadata;
                unless ($vars->{deleted} and $setting->{deletedRecord} eq 'no') {
                    return render(\$template_get_record, $vars);
                }
            }
            push @$errors, [idDoesNotExist => "identifier $params->{identifier} is unknown or illegal"];
            return render(\$template_error, $vars);

        } elsif ($verb eq 'Identify') {
            return render(\$template_identify, $vars);

        } elsif ($verb eq 'ListIdentifiers' || $verb eq 'ListRecords') {
            my $limit = $setting->{limit} // $DEFAULT_LIMIT;
            my $start = $vars->{start} //= 0;
            my $from  = $params->{from};
            my $until = $params->{until};

            for my $datestamp (($from, $until)) {
                $datestamp || next;
                if ($datestamp !~ /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}Z)?$/) {
                    push @$errors, [badArgument => "datestamps must have the format YYYY-MM-DD or YYYY-MM-DDThh:mm:ssZ"];
                    return render(\$template_error, $vars);
                };
            }

            if ($from && $until && length($from) != length($until)) {
                push @$errors, [badArgument => "datestamps must have the same granularity"];
                return render(\$template_error, $vars);
            }

            if ($from && $until && $from gt $until) {
                push @$errors, [badArgument => "from is more recent than until"];
                return render(\$template_error, $vars);
            }

            if ($from && length($from) == 10) {
                $from = "${from}T00:00:00Z";
            }
            if ($until && length($until) == 10) {
                $until = "${until}T00:00:00Z";
            }

            my @cql;
            my $cql_from  = $from;
            my $cql_until = $until;
            if (my $pattern = $setting->{datestamp_pattern}) {
                $cql_from  = DateTime::Format::Strptime::strftime($pattern, parse_oai_datestamp($cql_from))  if $cql_from;
                $cql_until = DateTime::Format::Strptime::strftime($pattern, parse_oai_datestamp($cql_until)) if $cql_until;
            }

            push @cql, qq|($setting->{cql_filter})|                      if $setting->{cql_filter};
            push @cql, qq|($set->{cql})|                                 if $set && $set->{cql};
            push @cql, qq|($setting->{datestamp_field} >= "$cql_from")|  if $cql_from;
            push @cql, qq|($setting->{datestamp_field} <= "$cql_until")| if $cql_until;
            unless (@cql) {
                push @cql, "(cql.allRecords)";
            }

            my $search = $bag->search(
                %{ $setting->{default_search_params} },
                cql_query => join(' and ', @cql),
                limit     => $limit,
                start     => $start,
            );

            unless ($search->total) {
                push @$errors, [noRecordsMatch => "no records found"];
                return render(\$template_error, $vars);
            }

            if ($start + $limit < $search->total) {
                $vars->{token} = join '!',
                    $params->{set} || '',
                    $from ? $from : '',
                    $until ? $until : '',
                    $params->{metadataPrefix},
                    $start + $limit;
            }

            $vars->{total} = $search->total;

            if ($verb eq 'ListIdentifiers') {
                $vars->{records} = [map {
                    my $rec = $_;
                    if ($fix) {
                        $rec = Catmandu->fixer($fix)->fix($rec);
                    }
                    {
                        id        => $rec->{_id},
                        datestamp => $format_datestamp->($rec->{$setting->{datestamp_field}}),
                        deleted   => $sub_deleted->($rec),
                        setSpec   => $sub_set_specs_for->($rec),
                    };
                } @{$search->hits}];
                return render(\$template_list_identifiers, $vars);
            } else {
                $vars->{records} = [map {
                    my $rec = $_;

                    if ($fix) {
                        $rec = Catmandu->fixer($fix)->fix($rec);
                    }

                    my $deleted = $sub_deleted->($rec);
                    my $metadata;
                    unless ($deleted) {
                        $metadata = "";
                        my $exporter = Catmandu::Exporter::Template->new(
                            template => $format->{template},
                            file     => \$metadata,
                            fix      => $format->{fix},
                        );
                        $exporter->add($rec);
                        $exporter->commit;
                    }
                    {
                        id        => $rec->{_id},
                        datestamp => $format_datestamp->($rec->{$setting->{datestamp_field}}),
                        deleted   => $deleted,
                        setSpec   => $sub_set_specs_for->($rec),
                        metadata  => $metadata,
                    };
                } @{$search->hits}];
                return render(\$template_list_records, $vars);
            }

        } elsif ($verb eq 'ListMetadataFormats') {
            if (my $id = $params->{identifier}) {
                $id =~ s/^$ns//;
                unless ($bag->get($id)) {
                    push @$errors, [idDoesNotExist => "identifier $params->{identifier} is unknown or illegal"];
                    return render(\$template_error, $vars);
                }
            }
            return render(\$template_list_metadata_formats, $vars);

        } elsif ($verb eq 'ListSets') {
            return render(\$template_list_sets, $vars);
        }
    }
};

register oai_provider => \&oai_provider;

register_plugin;

1;

=head1 SYNOPSIS

    use Dancer;
    use Dancer::Plugin::Catmandu::SRU;

    oai_provider '/oai';


=head1 CONFIGURATION

    plugins:
        'Catmandu::OAI':
            store: oai
            bag: publication
            datestamp_field: date_updated
            datestamp_pattern: "%Y-%H-%M %H:%M:%S"
            repositoryName: "My OAI Service Provider"
            uri_base: "http://oai.service.com/oai"
            adminEmail: me@example.com
            earliestDatestamp: "1970-01-01T00:00:01Z"
            deletedRecord: persistent
            repositoryIdentifier: oai.service.com
            limit: 200
            delimiter: ":"
            sampleIdentifier: "oai:oai.service.com:1585315"
            cql_filter: 'status exact public'
            get_record_cql_pattern: 'id exact "%s"'
            metadata_formats:
                -
                    metadataPrefix: oai_dc
                    schema: "http://www.openarchives.org/OAI/2.0/oai_dc.xsd"
                    metadataNamespace: "http://www.openarchives.org/OAI/2.0/oai_dc/"
                    template: views/oai_dc.tt
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

=head1 SEE ALSO

L<Dancer::Plugin::Catmandu::SRU>, L<Catmandu>, L<Catmandu::Store>

=head1 AUTHOR

Nicolas Steenlant, C<< <nicolas.steenlant at ugent.be> >>

=head1 CONTRIBUTORS

Nicolas Franck, C<< <nicolas.franck at ugent.be> >>

Vitali Peil, C<< <vitali.peil at uni-bielefeld.de> >>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
