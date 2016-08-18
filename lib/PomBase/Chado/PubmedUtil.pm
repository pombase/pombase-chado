package PomBase::Chado::PubmedUtil;

=head1 NAME

PomBase::Chado::PubmedUtil - Utilities for accessing pubmed.

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Chado::PubmedUtil

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009-2013 University of Cambridge, all rights reserved.

Canto is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

=head1 FUNCTIONS

=cut

use Carp;
use Moose;
use feature ':5.10';

use Text::CSV;
use XML::Simple;
use LWP::UserAgent;

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::XrefStorer';

has verbose => (is => 'rw');

my $max_batch_size = 10;

sub _get_url
{
  my $url = shift;

  my $ua = LWP::UserAgent->new;
  $ua->agent('PomBase');

  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);

  if ($res->is_success) {
    if ($res->content()) {
      return $res->content();
    } else {
      die "query returned no content: $url";
    }
  } else {
    die "Couldn't read from $url: ", $res->status_line, "\n";
  }
}

=head2 get_pubmed_xml_by_ids

 Usage   : my $xml = $pubmed_util->get_pubmed_xml_by_ids(@ids);
 Function: Return an XML chunk from pubmed with information about the
           publications with IDs given by @ids
 Args    : @ids - the pubmed ids to search for
 Returns : The XML from pubmed

=cut
sub get_pubmed_xml_by_ids
{
  my $self = shift;

  my @ids = @_;

  my $pubmed_query_url =
    $self->config()->{external_sources}->{pubmed_efetch_url};

  my $url = $pubmed_query_url . join(',', @ids);

  return _get_url($url);
}

=head2 get_pubmed_ids_by_query

 Usage   : my $xml = $pubmed_util->get_pubmed_ids_by_query($text);
 Function: Return a list of PubMed IDs of the articles that match the given
           text (in the title or abstract)
 Args    : $text - the query
 Returns : XML containing the matching IDs

=cut
sub get_pubmed_ids_by_query
{
  my $self = shift;
  my $text = shift;

  my $pubmed_query_url =
    $self->config()->{external_sources}->{pubmed_esearch_url};

  my $url = $pubmed_query_url . $text;

  return _get_url($url);
}


our $PUBMED_PREFIX = "PMID";

=head2 load_pubmed_xml

 Usage   : my $count = PomBase::Chado::PubmedUtil::load_pubmed_xml($schema, $xml);
 Function: Load the given pubmed XML in the database
 Args    : $schema - the schema to load into
           $xml - a string holding an XML fragment about containing some
                  publications from pubmed
 Returns : the count of number of publications loaded

=cut
sub load_pubmed_xml
{
  my $self = shift;
  my $content = shift;

  my %pub_type_cache = ();

  my $res_hash = XMLin($content,
                       ForceArray => ['AbstractText',
                                      'Author', 'PublicationType']);

  my $count = 0;
  my @articles;

  if (defined $res_hash->{PubmedArticle}) {
    if (ref $res_hash->{PubmedArticle} eq 'ARRAY') {
      @articles = @{$res_hash->{PubmedArticle}};
    } else {
      push @articles, $res_hash->{PubmedArticle};
    }

    for my $article (@articles) {
      my $medline_citation = $article->{MedlineCitation};
      my $uniquename = "$PUBMED_PREFIX:" . $medline_citation->{PMID}->{content};

      if (!defined $uniquename) {
        die "PubMed ID not found in XML\n";
      }

      my $article = $medline_citation->{Article};
      my $title = $article->{ArticleTitle};

      if (!defined $title || length $title == 0) {
        warn "No title for $uniquename - can't load";
        next;
      }

      my $affiliation = $article->{Affiliation} // '';

      my $authors = '';
      my $author_detail = $article->{AuthorList}->{Author};
      if (defined $author_detail) {
        my @author_elements = @{$author_detail};
        $authors = join ', ', map {
          if (defined $_->{CollectiveName}) {
            $_->{CollectiveName};
          } else {
            if (defined $_->{LastName}) {
              if (defined $_->{Initials}) {
                $_->{LastName} . ' ' . $_->{Initials};
              } else {
                $_->{LastName};
              }
            } else {
              warn "missing author details in: $uniquename\n";
              ();
            }
          }
        } @author_elements;
      }

      my $abstract_text = $article->{Abstract}->{AbstractText};
      my $abstract;

      if (ref $abstract_text eq 'ARRAY') {
        $abstract = join ("\n",
                          map {
                            if (ref $_ eq 'HASH') {
                              if (defined $_->{content}) {
                                $_->{content};
                              } else {
                                ();
                              }
                            } else {
                              $_;
                            }
                          } @$abstract_text);
      } else {
        $abstract = $abstract_text // '';
      }

      my $pubmed_type;

      my @publication_types =
        @{$article->{PublicationTypeList}->{PublicationType}};

      for my $type (@publication_types) {
        # warn "pub type: $pubmed_type\n";
      }

      my $citation = '';
      my $publication_date = '';

      if (defined $article->{Journal}) {
        my $journal = $article->{Journal};
        $citation =
          $journal->{ISOAbbreviation} // $journal->{Title} //
          'Unknown journal';

        if (defined $journal->{JournalIssue}) {
          my $journal_issue = $journal->{JournalIssue};
          my $pub_date = $journal_issue->{PubDate};

          if (defined $pub_date) {
            my $pub_date = $journal_issue->{PubDate};
            my @date_bits = ($pub_date->{Year} // (),
                             $pub_date->{Month} // (),
                             $pub_date->{Day} // ());

            if (!@date_bits) {
              my $medline_date = $pub_date->{MedlineDate};
              if (defined $medline_date &&
                  $medline_date =~ /(\d\d\d\d)(?:\s+(\w+)(?:\s+(\d+))?)?/) {
                @date_bits = ($1, $2 // (), $3 // ());
              }
            }

            my $cite_date = join (' ', @date_bits);
            $citation .= ' ' . $cite_date;

            $publication_date = join (' ', reverse @date_bits);
          }
          $citation .= ';';
          if (defined $journal_issue->{Volume}) {
            $citation .= $journal_issue->{Volume};
          }
          if (defined $journal_issue->{Issue}) {
            $citation .= '(' . $journal_issue->{Issue} . ')';
          }
        }
      }

      if (defined $article->{Pagination}) {
        my $pagination = $article->{Pagination};
        if (defined $pagination->{MedlinePgn} &&
            !ref $pagination->{MedlinePgn}) {
          $citation .= ':' . $pagination->{MedlinePgn};
        }
      }

      my $pub = $self->chado()->resultset('Pub::Pub')->find({ uniquename => $uniquename });

      $pub->title($title);

      $self->create_pubprop($pub, 'pubmed_publication_date', $publication_date);
      $self->create_pubprop($pub, 'pubmed_authors', $authors);
      $self->create_pubprop($pub, 'pubmed_citation', $citation);
      $self->create_pubprop($pub, 'pubmed_abstract', $abstract);

      $pub->update();

      $count++;
    }
  }

  return $count;
}

sub _process_batch
{
  my $self = shift;

  my $ids = shift;
  my @ids = @$ids;

  my $count = 0;

  my $content = $self->get_pubmed_xml_by_ids(@ids);
  $count += $self->load_pubmed_xml($content);

  return $count;
}

=head2 load_by_ids

 Usage   : my $count = PomBase::Chado::PubmedUtil::load_by_ids(...)
 Function: Load the publications with the given ids into the track
           database.
 Args    : $config - the config object
           $schema - the TrackDB object
           $ids - an array ref of ids of publications to load, with
                  optional "PMID:" prefix
 Returns : a count of the number of publications found and loaded

=cut
sub load_by_ids
{
  my $self = shift;
  my $ids = shift;

  my $count = 0;

  while (@$ids) {
    my @process_ids = map { s/^PMID://; $_; } splice(@$ids, 0, $max_batch_size);

    $count += $self->_process_batch([@process_ids]);
  }

  return $count;
}

=head2 load_by_query

 Usage   : my $count = PomBase::Chado::PubmedUtil::load_by_query(...)
 Function: Send a query to PubMed and load the publications it returns
           into the track database.
 Args    : $config - the config object
           $schema - the TrackDB object
           $query - a PubMed query string
 Returns : a count of the number of publications found and loaded

=cut
sub load_by_query
{
  my $self = shift;

  my $config = $self->config();
  my $schema = $self->chado();

  my $query = shift;

  my $count = 0;

  my $xml = $self->get_pubmed_ids_by_query($config, $query);
  my $res_hash = XMLin($xml);

  if (!defined $res_hash->{IdList}->{Id}) {
    my $warning_list = $res_hash->{WarningList};
    if (defined $warning_list) {
      my $output_mesasge = $warning_list->{OutputMessage};
      if (ref $output_mesasge eq 'ARRAY') {
        die join ('  ', @$output_mesasge), "\n";;
      } else {
        die "$output_mesasge\n";
      }
    }

    die "PubMed query failed, but returned no error\n";
  }

  my @ids = @{$res_hash->{IdList}->{Id}};

  while (@ids) {
    my @process_ids = splice(@ids, 0, $max_batch_size);

    $count += $self->_process_batch([@process_ids]);
  }

  return $count;
}


=head2

 Usage   : my $count = $pubmed_util->add_missing_fields();
 Function: Find publications in the pub table that have no title, query pubmed
           for the missing information and then set the titles
 Return  : the number of titles added, dies on error

=cut
sub add_missing_fields
{
  my $self = shift;

  my $config = $self->config();
  my $chado = $self->chado();

  my $rs = $chado->resultset('Pub::Pub')->search({
    -or => [
      title => undef,
    ],
    uniquename => { -like => 'PMID:%' },
   });
  my $max_batch_size = 300;
  my $count = 0;

  return $self->load_by_ids([map { $_->uniquename() } $rs->all()]);
}

1;
