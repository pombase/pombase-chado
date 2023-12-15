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
use Storable qw(freeze thaw);

use Text::CSV;
use XML::Simple;
use LWP::UserAgent;
use List::Util qw(uniq);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::FeatureStorer';

has verbose => (is => 'rw');
has pubmed_cache => (is => 'rw', required => 1);

my $max_batch_size = 200;

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

sub _remove_tag {
  my $text = shift;
  $text =~ s/<[^>]+>/ /g;
  return $text;
}

=head2 parse_pubmed_xml

 Usage   : $self->parse_pubmed_xml($xml);
 Function: Parse the given pubmed XML and store in the cache
 Args    : $xml - publication XML from pubmed

=cut
sub parse_pubmed_xml
{
  my $self = shift;
  my $content = shift;

  # Awful hack to remove italics and other tags in titles and abstracts.
  # This prevents parsing problems, see:
  # https://github.com/pombase/pombase-chado/issues/663
  for my $tag_name ('ArticleTitle', 'AbstractText') {
    $content =~ s|<$tag_name>(.+?)</$tag_name>|"<$tag_name>" . _remove_tag($1) . "</$tag_name>"|egs;
  }

  my $res_hash = XMLin($content,
                       ForceArray => ['AbstractText', 'ELocationID',
                                      'Author', 'PublicationType']);

  my @articles;

  my $article_hash = $res_hash->{PubmedArticle};

  if (defined $article_hash) {
    if (ref $article_hash eq 'ARRAY') {
      @articles = @{$article_hash};
    } else {
      push @articles, $article_hash;
    }

    for my $article (@articles) {
      my $medline_citation = $article->{MedlineCitation};
      my $uniquename = "$PUBMED_PREFIX:" . $medline_citation->{PMID}->{content};

      if (!defined $uniquename) {
        die "PubMed ID not found in XML\n";
      }

      my $pubmed_data = $article->{PubmedData};

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
                                if (ref $_->{content}) {
                                  ();
                                } else {
                                  $_->{content};
                                }
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

      my $pubmed_pub_type;

      my @publication_types =
        @{$article->{PublicationTypeList}->{PublicationType}};

      if (@publication_types > 0) {
        $pubmed_pub_type = $publication_types[0];
      }

      my $citation = '';
      my $journal_title = undef;
      my $publication_date = '';

      if (defined $article->{Journal}) {
        my $journal = $article->{Journal};
        $journal_title = $journal->{Title};
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

      my $epub_date = undef;

      my $article_date = $article->{ArticleDate};

      if ($article_date && defined $article_date->{DateType} &&
            lc $article_date->{DateType} eq 'electronic') {

        my $art_year = $article_date->{Year};
        my $art_month = $article_date->{Month};
        my $art_day = $article_date->{Day};

        if ($art_day) {
          $epub_date = "$art_year-$art_month-$art_day";
        } else {
          if ($art_month) {
            $epub_date = "$art_year-$art_month";
          } else {
            $epub_date = $art_year;
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

      my $doi = undef;

      my $elocationids = $article->{ELocationID};

      if ($elocationids) {
        my @doi_ids =
          grep {
            $_->{EIdType} eq 'doi' && uc $_->{ValidYN} eq 'Y';
          } @{$elocationids};

        if (@doi_ids > 0) {
          $doi = $doi_ids[0]->{content};
        }
      }

      my $pubmed_entrez_date = undef;

      if ($pubmed_data && $pubmed_data->{History} &&
            $pubmed_data->{History}->{PubMedPubDate}) {
        for my $pubmed_pub_date (@{$pubmed_data->{History}->{PubMedPubDate}}) {
          if ($pubmed_pub_date->{PubStatus} && $pubmed_pub_date->{PubStatus} eq 'entrez') {
            if (defined $pubmed_pub_date->{Year} && defined $pubmed_pub_date->{Month} &&
                  defined $pubmed_pub_date->{Day}) {
              $pubmed_entrez_date = sprintf "%04s-%02s-%02s",
                $pubmed_pub_date->{Year}, $pubmed_pub_date->{Month}, $pubmed_pub_date->{Day};
            }
          }
        }
      }

      my $keyword_list = $medline_citation->{KeywordList};

      my @keywords = ();

      if (defined $keyword_list) {
        my $keyword_array = $keyword_list->{Keyword};

        if (defined $keyword_array) {
          if (ref $keyword_array ne 'ARRAY') {
            $keyword_array = [$keyword_array];
          }

          @keywords =
            uniq
            map {
              split /\s*,\s*/;
            }
            map {
              $_->{content};
            }
            grep {
              defined $_->{content};
            } @{$keyword_array};
        }
      }

      my $pub = $self->chado()->resultset('Pub::Pub')->find({ uniquename => $uniquename });

      $self->pubmed_cache()->{$uniquename} = freeze({
        title => $title,
        publication_date => $publication_date,
        epub_date => $epub_date,
        pubmed_entrez_date => $pubmed_entrez_date,
        authors => $authors,
        pub_type => $pubmed_pub_type,
        citation => $citation,
        journal_title => $journal_title,
        abstract => $abstract,
        doi => $doi,
        keywords => \@keywords,
      });
    }
  }
}

sub _process_batch
{
  my $self = shift;

  my $ids = shift;
  my @ids = @$ids;

  my $content = $self->get_pubmed_xml_by_ids(@ids);
  $self->parse_pubmed_xml($content);
}

sub _store_from_cache
{
  my $self = shift;
  my $taxonid = shift;
  my $ids = shift;

  my $cache = $self->pubmed_cache();

  my $count = 0;

  for my $id (@$ids) {
    my $uniquename = "$PUBMED_PREFIX:$id";
    my $pub_details = thaw($cache->{$uniquename});

    if ($pub_details) {
      my $pub = $self->chado()->resultset('Pub::Pub')->find({ uniquename => $uniquename });

      $pub->title($pub_details->{title});
      $pub->miniref($pub_details->{citation});
      $pub->update();

      $self->create_pubprop($pub, 'pubmed_publication_date', $pub_details->{publication_date});
      if ($pub_details->{epub_date}) {
        $self->create_pubprop($pub, 'pubmed_electronic_publication_date', $pub_details->{epub_date});
      }
      if ($pub_details->{pubmed_entrez_date}) {
        $self->create_pubprop($pub, 'pubmed_entrez_date', $pub_details->{pubmed_entrez_date});
      }
      $self->create_pubprop($pub, 'pubmed_authors', $pub_details->{authors});
      $self->create_pubprop($pub, 'pubmed_citation', $pub_details->{citation});
      $self->create_pubprop($pub, 'pubmed_abstract', $pub_details->{abstract});

      if (defined $pub_details->{doi}) {
        $self->create_pubprop($pub, 'pubmed_doi', $pub_details->{doi});
      }

      my @lc_keywords = map { lc $_ } @{$pub_details->{keywords}};

      for my $lc_keyword (@lc_keywords) {
        if ($lc_keyword =~ /(.*)p$/i) {
          # some protein names end in "p" like "Cdc11p"
          push @lc_keywords, $1;
        }
      }

      my $organism_rs =
        $self->chado()->resultset('Organism::Organismprop')
        ->search({ 'type.name' => 'taxon_id',
                   value => $taxonid,
                 },
                 { join => [ 'type' ] })
        ->search_related('organism');

      my $keyword_gene_rs =
        $self->chado()->resultset('Sequence::Feature')
        ->search( { 'type.name' => 'gene',
                     -or => [
                      { 'LOWER(me.uniquename)' => \@lc_keywords },
                      { 'LOWER(me.name)' => \@lc_keywords },
                    ],
                    organism_id => {
                      '=' => $organism_rs->get_column('organism_id')->as_query()
                    },
                  },
                  {
                    join => ['type']
                  });

      while (defined (my $keyword_gene = $keyword_gene_rs->next())) {
        my $feature_pub = $self->find_or_create_feature_pub($keyword_gene, $pub);
        $self->store_feature_pubprop($feature_pub, 'feature_pub_source',
                                        'pubmed_keyword');
      }

      $count++;
    }
  }

  return $count;
}

=head2 load_by_ids

 Usage: my $count = PomBase::Chado::PubmedUtil::load_by_ids(...)
 Function: Load the publications with the given ids into the
           database.
 Args    : $taxonid - the taxon ID to use when looking up genes from the
                      PubMed keywords
           $ids - an array ref of ids of publications to load, with
                  optional "PMID:" prefix
 Returns : a count of the number of publications found and loaded

=cut
sub load_by_ids
{
  my $self = shift;
  my $taxonid = shift;
  my $ids = shift;

  my @raw_ids = map { s/^PMID://; $_; } @$ids;

  my @ids_to_fetch =
    grep {
      s/^.*?(\d+).*?$/$1/;  # remove any excess characters
      !exists $self->pubmed_cache()->{"PMID:$_"};
    } @raw_ids;

  while (@ids_to_fetch) {
    my @process_ids = splice(@ids_to_fetch, 0, $max_batch_size);

    $self->_process_batch(\@process_ids);

    sleep(10);
  }

  return $self->_store_from_cache($taxonid, \@raw_ids);
}

=head2 load_by_query

 Usage   : my $count = PomBase::Chado::PubmedUtil::load_by_query(...)
 Function: Send a query to PubMed and load the publications it returns
           into the database.
 Args    : $query - a PubMed query string
 Returns : a count of the number of publications found and loaded

=cut
sub load_by_query
{
  my $self = shift;

  my $config = $self->config();
  my $schema = $self->chado();

  my $taxonid = $config->{taxonid};

  my $query = shift;

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

    $self->_process_batch(\@process_ids);
  }

  $self->_store_from_cache($taxonid, \@ids);
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

  my %args = @_;

  my $taxonid = $args{taxonid};

  if (!defined $taxonid) {
    die "no taxon ID passed to add_missing_fields()";
  }

  my $config = $self->config();
  my $chado = $self->chado();

  my $rs = $chado->resultset('Pub::Pub')->search({
    -or => [
      title => undef,
      miniref => undef,
    ],
    uniquename => { -like => 'PMID:%' },
   });

  my $missing_count = $rs->count();

  my $loaded_count = $self->load_by_ids($taxonid, [map { $_->uniquename() } $rs->all()]);

  return ($missing_count, $loaded_count);
}

1;
