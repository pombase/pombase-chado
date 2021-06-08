package PomBase::Retrieve::GeneAssociationFile;

=head1 NAME

PomBase::Retrieve::GeneAssociationFile - Retrieve GO annotation from
           Chado and generate a GAF format file

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::GeneAssociationFile

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;

use feature qw(state);

use Moose;
use feature 'state';

use Getopt::Long qw(GetOptionsFromArray :config pass_through);

use Iterator::Simple qw(iterator);

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';
with 'PomBase::Role::ExtensionDisplayer';

my @go_cv_names = qw(biological_process cellular_component molecular_function);
my $ext_cv_name = 'PomBase annotation extension terms';

has filter_by_term => (is => 'rw');
has filter_term_by_sql => (is => 'rw');

sub BUILDARGS
{
  my $class = shift;
  my %args = @_;

  my $filter_by_term = undef;
  my $filter_term_by_sql = undef;

  my @opt_config = ("filter-by-term=s" => \$filter_by_term,
                    "filter-term-by-sql=s" => \$filter_term_by_sql);

  if (!GetOptionsFromArray($args{options}, @opt_config)) {
    croak "option parsing failed";
  }

  $args{filter_by_term} = $filter_by_term;
  $args{filter_term_by_sql} = $filter_term_by_sql;

  return \%args;
}

sub _get_feature_details {
  my $self = shift;
  my %synonyms = ();

  my $syn_rs = $self->chado()->resultset('Sequence::FeatureSynonym')->
    search({ 'feature.organism_id' => $self->organism()->organism_id(),
             is_current => 1, },
           { join => 'feature', prefetch => [ 'synonym' ] });

  map {
    push @{$synonyms{$_->feature_id()}}, $_->synonym()->name();
  } $syn_rs->all();

  my %products = ();

  my $products_rs = $self->chado()->resultset('Sequence::FeatureCvterm')->
    search({ 'cv.name' => 'PomBase gene products' },
           { join => { cvterm => 'cv' },
             prefetch => [ 'cvterm', 'feature' ] });

  map {
    my $uniquename = $_->feature()->uniquename();
    $uniquename =~ s/\.\d+(:pep)?$//;
    $products{$uniquename} = $_->cvterm()->name();
  } $products_rs->all();

  my %statuses = ();

  my $statuses_rs = $self->chado()->resultset('Sequence::FeatureCvterm')->
    search({ 'cv.name' => 'PomBase gene characterisation status' },
           { join => { cvterm => 'cv' },
             prefetch => [ 'cvterm', 'feature' ] });

  map {
    my $uniquename = $_->feature()->uniquename();
    $uniquename =~ s/\.\d+(:pep)?$//;
    $statuses{$uniquename} = $_->cvterm()->name();
  } $statuses_rs->all();


  my %ret_map = ();

  my $gene_rs = $self->chado()->resultset('Sequence::FeatureRelationship')->
    search(
      {
        -and => {
          'subject.organism_id' => $self->organism()->organism_id(),
          -or => [
            'type_3.name' => 'gene',
            'type_3.name' => 'pseudogene',
          ],
          'type_2.name' => 'part_of',
        },
      },
      {
        join => [ { subject => 'type' }, 'type', { object => 'type' } ],
        prefetch => [ { subject => 'type' }, { object => 'type' }, 'type' ] });

  map {
    my $rel = $_;
    my $object = $rel->object();
    my $subject = $rel->subject();
    my $type = $rel->type();
    if ($type->name() eq 'part_of') {
      if (defined $ret_map{$rel->subject_id()}->{gene}) {
        die "feature has two part_of parents";
      } else {
        $ret_map{$rel->subject_id()} = {
          gene => $object,
          type => $object->type()->name(),
          transcript_type => $subject->type()->name(),
          synonyms => $synonyms{$object->feature_id()},
          product => $products{$object->uniquename()} // '',
          status => $statuses{$object->uniquename()} // '',
        };
      }
    }
  } $gene_rs->all();

  return %ret_map;
}

sub _safe_join {
  my $expr = shift;
  my $array = shift;

  if (defined $array) {
    return join $expr, @{$array};
  } else {
    return '';
  }
}

sub _get_qualifier {
  my $self = shift;
  my $fc = shift;
  my $fc_props = shift;

  my @qual_bits;

  if (defined $fc_props->{qualifier}) {
    @qual_bits = grep {
      $self->config()->{geneontology_qualifier_flags}->{$_};
    } @{$fc_props->{qualifier}};
  } else {
    @qual_bits = ();
  }

  if ($fc->is_not()) {
    push @qual_bits, "NOT"
  }

  join('|', @qual_bits);
}

sub _fix_with {
  my $db_name = shift;
  my $with = shift;

  if ($with =~ /:/) {
    if ($with =~ /GeneDB_Spombe/) {
      die qq("GeneDB_Spombe:" from "$with" is obsolete\n);
    }
    return $with;
  } else {
    $db_name . ':' . $with;
  }
}

sub _lookup_term {
  my $self = shift;
  my $term_id = shift;

  state $cache = {};

  if (exists $cache->{$term_id}) {
    return $cache->{$term_id};
  } else {
    my $chado = $self->chado();
    my $term = $chado->resultset('Cv::Cvterm')->find($term_id);
    $cache->{$term_id} = $term;
    return $term;
  }
}

sub _fix_date {
  my $date = shift;

  if ($date =~ /(\d+)-(\d+)-(\d+)/) {
    return "$1$2$3";
  } else {
    return $date;
  }
}

my %cv_abbreviations = (biological_process => 'P',
                        cellular_component => 'C',
                        molecular_function => 'F',
                      );

my %top_level_terms = (P => 'GO:0008150',
                       C => 'GO:0005575',
                       F => 'GO:0003674',
                     );

my @ncrna_so_types = qw(ncRNA snRNA snoRNA rRNA tRNA);
my %so_type_map = (mRNA => "protein",
                   map { ($_, $_) } @ncrna_so_types);

sub _make_nd_rows {
  my $feature_details = shift;
  my $gene_aspect_counts = shift;

  my @rows = ();
  my %dup_check = ();

  for my $feature_id (keys %$feature_details) {
    my $feature_details = $feature_details->{$feature_id};
    my $gene_uniquename = $feature_details->{gene}->uniquename();
    my $gene_name = $feature_details->{gene}->name();

    next if $dup_check{$gene_uniquename};

    $dup_check{$gene_uniquename} = 1;

    if (!exists $gene_aspect_counts->{$gene_uniquename} &&
        $feature_details->{transcript_type} eq 'ncRNA') {
      # if there are no annotation for an ncRNA, ignore it
      next;
    }

    for my $aspect_name (keys %cv_abbreviations) {
      my $aspect_abbrev = $cv_abbreviations{$aspect_name};
      if (!exists $gene_aspect_counts->{$gene_uniquename}{$aspect_abbrev}) {
        push @rows, {
          feature_details => $feature_details,
          aspect => $aspect_abbrev,
        }
      }
    }
  }

  return \@rows;
}

sub _current_date {
  my($day, $month, $year)=(localtime)[3,4,5];
  return sprintf "%04d%02d%02d", ($year+1900), ($month+1), ($day);
}

sub retrieve {
  my $self = shift;

  my $chado = $self->chado();

  my $db_name = $self->config()->{database_name};

  if (!defined $db_name) {
    die qq(For GAF export the "database_name" option must be set in the ) .
      "configuration file\n";
  }

  my $taxon = 'taxon:' . $self->organism_taxonid();
  my $date_now = _current_date();

  my %feature_details = $self->_get_feature_details();

  my %gene_aspect_count = ();

  my $it = do {
    my $cv_rs =
      $chado->resultset('Cv::Cv')->search([
        map { { 'me.name' => $_ } } (@go_cv_names, $ext_cv_name)
      ]);

    my $cvterm_rs =
      $chado->resultset('Cv::Cvterm')->search(
        {
          cv_id => { -in => $cv_rs->get_column('cv_id')->as_query() }
        }
      );

    if ($self->filter_by_term()) {
      if (my ($db_name, $accession) = $self->filter_by_term() =~ /^(\w+):(\d+)$/) {
        my $where =
          "\
me.cvterm_id in
(select res_terms.cvterm_id from pombase_feature_cvterm_ext_resolved_terms res_terms
 join cvtermpath cp on cp.subject_id = res_terms.base_cvterm_id
 join cvterm t on cp.object_id = t.cvterm_id
 join dbxref x on x.dbxref_id = t.dbxref_id
 join db on x.db_id = db.db_id
 where db.name = '$db_name' and x.accession = '$accession')";
        $cvterm_rs = $cvterm_rs->search({}, {
          where => \$where,
        });
      }
    }

    if ($self->filter_term_by_sql()) {
      my $where = 'me.cvterm_id in (' . $self->filter_term_by_sql() . ')';
      $cvterm_rs = $cvterm_rs->search({}, {
        where => \$where,
      });
    }

    my $feature_cvterm_rs =
      $chado->resultset('Sequence::FeatureCvterm')->search(
        {
          'me.cvterm_id' => { -in => $cvterm_rs->get_column('cvterm_id')->as_query() }
        });

    my %fc_props = ();

    my $fc_props_rs = $feature_cvterm_rs->search_related('feature_cvtermprops');
    my %types_by_id = ();

    while (defined (my $prop = $fc_props_rs->next())) {
      my $type = $self->_lookup_term($prop->type_id());
      push @{$fc_props{$prop->feature_cvterm_id()}->{$type->name()}}, $prop->value();
    }

    my $results =
      $feature_cvterm_rs->search({},
        {
          prefetch => [ 'feature', 'pub', { cvterm => [ 'cv', { dbxref => 'db' } ] } ]
        },
      );

    my $nd_rows = undef;

    iterator {
    ROW: {
      my $row = $results->next();

      if (defined $row) {
        my ($extensions, $base_cvterm) = $self->make_gaf_extension($row);

        my $fc_id = $row->feature_cvterm_id();
        my %row_fc_props = %{$fc_props{$fc_id}};
        my $cvterm = $base_cvterm // $row->cvterm();
        my $cv_name = $cvterm->cv()->name();

        if (!grep { $_ eq $cv_name } @go_cv_names) {
          goto ROW;
        }

        my $feature = $row->feature();
        my $details = $feature_details{$feature->feature_id()};

        if (!defined $details) {
          warn "can't find details for: ", $feature->uniquename(), "\n";
          goto ROW;
        }

        if ($details->{type} ne 'gene') {
          goto ROW;
        }

        my $qualifier = $self->_get_qualifier($row, \%row_fc_props);
        my $dbxref = $cvterm->dbxref();
        my $id = $dbxref->db()->name() . ':' . $dbxref->accession();
        my $evidence = _safe_join('|', $row_fc_props{evidence});
        if (!defined $evidence || length $evidence == 0) {
          warn "no evidence for ", $feature->uniquename(), " <-> ", $cvterm->name() , "\n";
          goto ROW;
        }
        my $evidence_code = $self->config()->{evidence_name_to_code}->{lc $evidence};
        if (!defined $evidence_code) {
          warn qq|can't find the evidence code for "$evidence"|;
          goto ROW;
        }
        my $aspect = $cv_abbreviations{$cv_name};
        my $pub = $row->pub();
        my $gene = $details->{gene} // die "no gene for ", $feature->uniquename();
        my $gene_uniquename = $gene->uniquename();
        my @fixed_with_from= map { _fix_with($db_name, $_) } (@{$row_fc_props{with}}, @{$row_fc_props{from}});
        my $with_from = _safe_join(',', [@fixed_with_from]);
        my $gene_name = $gene->name() // $gene_uniquename;
        my $synonyms_ref = $details->{synonyms} // [];
        my $synonyms = join '|', @{$synonyms_ref};
        my $product = $details->{product} // '';
        my $status = $details->{status} // '';

        if ($product eq 'dubious' or $status eq 'dubious') {
          goto ROW;
        }

        my $date = _safe_join('|', [map { _fix_date($_) } @{$row_fc_props{date}}]);
        my $gene_product_form_id = _safe_join('|', $row_fc_props{gene_product_form_id});
        my $so_type = $so_type_map{$details->{transcript_type}};
        my $assigned_by = _safe_join('|', $row_fc_props{assigned_by});

        if (!$row->is_not()) {
          $gene_aspect_count{$gene_uniquename}{$aspect}++;
        }

        return [$db_name, $gene_uniquename, $gene_name,
                $qualifier, $id, $pub->uniquename(),
                $evidence_code, $with_from, $aspect, $product, $synonyms,
                $so_type, $taxon, $date, $assigned_by, $extensions // '',
                $gene_product_form_id];
      } else {
        if (defined $self->filter_by_term() || defined $self->filter_term_by_sql()) {
          return undef;
        }

        if (!defined $nd_rows) {
          $nd_rows = _make_nd_rows(\%feature_details, \%gene_aspect_count);
        }

      ND_ROW: {
        my $row_data = pop @$nd_rows;

        if (defined $row_data) {
          my $feature_details = $row_data->{feature_details};

          if ($feature_details->{type} ne 'gene') {
            goto ND_ROW;
          }

          my $gene_uniquename = $feature_details->{gene}->uniquename();
          my $gene_name = $feature_details->{gene}->name();
          my $gene_product = $feature_details->{product};
          my $synonyms_ref = $feature_details->{synonyms} // [];
          my $synonyms = join '|', @{$synonyms_ref};
          my $aspect_abbrev = $row_data->{aspect};
          my $aspect_id = $top_level_terms{$aspect_abbrev};
          my $so_type = $so_type_map{$feature_details->{transcript_type}};

          my $gene_status = $feature_details->{status} // '';

          if ($gene_product eq 'dubious' or $gene_status eq 'dubious') {
            goto ND_ROW;
          }

          return [$db_name, $gene_uniquename,
                  $gene_name // $gene_uniquename,
                  '', $aspect_id, "GO_REF:0000015",
                  'ND', '', $aspect_abbrev, $gene_product, $synonyms,
                  $so_type, $taxon, $date_now, $db_name, '', '']
        } else {
          return undef;
        }
      }
      }
    }
    };
  };
}

sub header {
  my $self = shift;
  return '';
}

sub format_result {
  my $self = shift;
  my $res = shift;

  my $line = (join "\t", @$res);

  die "dubious $line!" if $line =~ /dubious/;

  return (join "\t", @$res);
}

1;
