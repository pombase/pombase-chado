package PomBase::Import::GeneAssociationFile;

=head1 NAME

PomBase::Import::GeneAssociationFile - Code for importing GAF files

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Import::GeneAssociationFile

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

use Text::CSV;
use Getopt::Long qw(GetOptionsFromArray);

with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';
with 'PomBase::Role::UniProtIDMap';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);
has assigned_by_filter => (is => 'rw', init_arg => undef);
has taxon_filter => (is => 'rw', init_arg => undef);
has remove_existing => (is => 'rw', init_arg => undef);
has use_first_with_id => (is => 'rw', init_arg => undef);
has with_filter_values => (is => 'rw', isa => 'HashRef',
                             init_arg => undef);
has term_id_filter_values => (is => 'rw', isa => 'HashRef',
                              init_arg => undef);

method _load_first_column($filename) {
  return unless $filename;

  my %ret_val = ();

  open my $file, '<', $filename
    or die "can't open $filename: $!\n";

  while (defined (my $line = <$file>)) {
    next if $line =~ /^\w*$/;
    if ($line =~ /^(\S+)/ and length $1 > 0) {
      $ret_val{$1} = 1;
    } else {
      warn "line from $filename has no columns: $line";
    }
  }

  close $file or die "$!";

  return %ret_val;
}

method BUILD {
  my $assigned_by_filter = '';
  my $taxon_filter = '';
  my $remove_existing = 0;
  my $with_filter_filename = undef;
  my $term_id_filter_filename = undef;

  # if true only the first ID from a with field will be stored
  my $use_first_with_id = 0;

  my @opt_config = ('assigned-by-filter=s' => \$assigned_by_filter,
                    'remove-existing' => \$remove_existing,
                    'taxon-filter=s' => \$taxon_filter,
                    'with-filter-filename=s' =>
                      \$with_filter_filename,
                    'term-id-filter-filename=s' =>
                      \$term_id_filter_filename,
                    'use-only-first-with-id' => \$use_first_with_id);

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  $assigned_by_filter =~ s/^\s+//;
  $assigned_by_filter =~ s/\s+$//;

  if (length $taxon_filter == 0) {
    warn "no taxon filter - annotation will be loaded for all taxa\n";
  }

  $self->assigned_by_filter([split /\s*,\s*/, $assigned_by_filter]);
  $self->taxon_filter([split /\s*,\s*/, $taxon_filter]);
  $self->remove_existing($remove_existing);

  my %with_filter_values =
    $self->_load_first_column($with_filter_filename);
  $self->with_filter_values({%with_filter_values});

  my %term_id_filter_values =
    $self->_load_first_column($term_id_filter_filename);
  $self->term_id_filter_values({%term_id_filter_values});

  $self->use_first_with_id($use_first_with_id);
}

method load($fh) {
  my $chado = $self->chado();
  my $config = $self->config();

  my @assigned_by_filter = @{$self->assigned_by_filter};
  my %assigned_by_filter = map { $_ => 1 } @assigned_by_filter;

  my $assigned_by_cvterm =
    $self->get_cvterm('feature_cvtermprop_type', 'assigned_by');

  my %deleted_counts = ();

  if ($self->remove_existing()) {
    for my $assigned_by (@assigned_by_filter) {
      my $assigned_by_rs = $chado->resultset('Sequence::FeatureCvtermprop')
        ->search({ 'me.type_id' => $assigned_by_cvterm->cvterm_id(),
                   'me.value' => $assigned_by });

      my $rs = $assigned_by_rs->search_related('feature_cvterm');

      my @fc_ids = map { $_->feature_cvterm_id() } $rs->all();
      my $fc_rs = $chado->resultset('Sequence::FeatureCvterm')
        ->search({ 'me.feature_cvterm_id' => { -in => [@fc_ids] }});

      $fc_rs->search_related('feature_cvtermprops')->delete();

      my $row_count = $fc_rs->delete() + 0;
      $deleted_counts{$assigned_by} = $row_count;
    }
  }

  my $csv = Text::CSV->new({ sep_char => "\t", allow_loose_quotes => 1 });

  $csv->column_names(qw(DB DB_object_id DB_object_symbol Qualifier GO_id DB_reference Evidence_code With_or_from Aspect DB_object_name DB_object_synonym DB_object_type Taxon Date Assigned_by Annotation_extension Gene_product_form_id ));

  my %with_filter = %{$self->with_filter_values()};
  my %term_id_filter = %{$self->term_id_filter_values()};

  my $use_first_with_id = $self->use_first_with_id();

 LINE:
  while (defined (my $line = $fh->getline())) {
    next if $line =~ /^\s*!/;

    if (!$csv->parse($line)) {
      die "Parse error at line $.: ", $csv->error_input(), "\n";
    }

    my %columns = ();

    @columns{ $csv->column_names() } = $csv->fields();

    my $taxonid = $columns{"Taxon"};

    if (!defined $taxonid) {
      warn "Taxon missing - skipping\n";
      next;
    }

    $taxonid =~ s/taxon://ig;

    if (!$taxonid->is_integer()) {
      warn "Taxon is not a number: $taxonid - skipping\n";
      next;
    }

    my $new_taxonid = $config->{organism_taxon_map}->{$taxonid};
    if (defined $new_taxonid) {
      $taxonid = $new_taxonid;
    }

    my @taxon_filter = @{$self->taxon_filter()};

    if (@taxon_filter > 0 && !grep { $_ == $taxonid; } @taxon_filter) {
      warn "skipping, wrong taxon: $taxonid at line $.\n" if $self->verbose();
      next;
    }

    my $db_object_id = $columns{"DB_object_id"};
    my $db_object_symbol = $columns{"DB_object_symbol"};
    my $qualifier = $columns{"Qualifier"};

    if (!defined $qualifier) {
      warn "The qualifier column has no value\n";
      next;
    }

    if ($qualifier =~ /\|/) {
      warn "annotation with multiple qualifiers ($qualifier)\n";
      next;
    }

    my $is_not = 0;

    if ($qualifier =~ /^not$/i) {
      $is_not = 1;
    }

    my $go_id = $columns{"GO_id"};

    if ($term_id_filter{$go_id}) {
      if ($self->verbose()) {
        warn "ignoring line because of term filter: $go_id\n";
      }
      next;
    }

    my $db_reference = $columns{"DB_reference"};

    my $evidence_code = $columns{"Evidence_code"};
    my $long_evidence =
      $self->config()->{evidence_types}->{$evidence_code}->{name};

    my $with_or_from_column = $columns{"With_or_from"};
    my @withs_and_froms = ();

    if (length $with_or_from_column > 0) {
      @withs_and_froms = split (/\|/, $with_or_from_column);
    }

    for (my $i = 0; $i < @withs_and_froms; $i++) {
      my $with_or_from = $withs_and_froms[$i];

      if ($with_filter{$with_or_from}) {
        if ($self->verbose()) {
          warn "ignoring line because of with filter: $with_or_from\n";
        }
        next LINE;
      }

      my $local_id = $self->lookup_uniprot_id($with_or_from);
      if (defined $local_id) {
        $withs_and_froms[$i] = $self->config()->{database_name} . ":$local_id";
      }
    }

    my $db_object_synonym = $columns{"DB_object_synonym"};

    my $date = $columns{"Date"};
    my $assigned_by = $columns{"Assigned_by"};

    if (@assigned_by_filter && !$assigned_by_filter{$assigned_by}) {
      if ($self->verbose()) {
        warn "ignoring line because of assigned_by filter: $assigned_by\n";
      }
      next;
    }

    my @synonyms = split /\|/, $db_object_synonym;

    push @synonyms, $db_object_id, $db_object_symbol;

    map { s/\s+$//; s/^\s+//; } @synonyms;

    my $uniquename_re = $config->{systematic_id_re};

    if (!defined $uniquename_re) {
      die "systematic_id_re configuration variable not set\n";
    }

    my $uniquename = undef;

    my $organism = $self->find_organism_by_taxonid($taxonid);

    if (!defined $organism) {
      warn "ignoring annotation for organism $taxonid\n";
      next;
    }

    my $feature;
    # try systematic ID first
    for my $synonym (@synonyms) {
      if ($synonym =~ /^($uniquename_re)/) {
        try {
          $feature = $self->find_chado_feature("$synonym.1", 1, 1, $organism);
        };

        last if defined $feature;
      }
    }

    if (!defined $feature) {
      for my $synonym (@synonyms) {
        try {
          $feature = $self->find_chado_feature("$synonym.1", 1, 1, $organism);
        } catch {
          # feature not found
        };

        last if defined $feature;
      }
    }

    if (!defined $feature) {
      warn "feature not found, no synonym matches a feature (" .
      "@synonyms)\n";
      next;
    }

    my $proc = sub {
      my $pub = $self->find_or_create_pub($db_reference);

      my $cvterm = $self->find_cvterm_by_term_id($go_id);

      if (!defined $cvterm) {
        warn "can't load annotation, $go_id not found in database\n";
        return;
      }

      my $feature_cvterm =
        $self->create_feature_cvterm($feature, $cvterm, $pub, $is_not);

      $self->add_feature_cvtermprop($feature_cvterm, 'assigned_by',
                                    $assigned_by);
      $self->add_feature_cvtermprop($feature_cvterm, 'date', $date);
      $self->add_feature_cvtermprop($feature_cvterm, 'evidence',
                                    $long_evidence);

      for (my $i = 0; $i < @withs_and_froms; $i++) {
        my $with_or_from = $withs_and_froms[$i];

        if ($use_first_with_id && $i > 0) {
          next;
        }

        $self->add_feature_cvtermprop($feature_cvterm, 'with',
                                      $with_or_from, $i);
      }
    };

    try {
      $chado->txn_do($proc);
    } catch {
      warn "Failed to load row: $_\n";
    }
  }

  if (!$csv->eof()){
    $csv->error_diag();
  }

  return \%deleted_counts;
}

method results_summary($results) {
  my $ret_val = '';

  for my $assigned_by (sort keys %$results) {
    my $count = $results->{$assigned_by};
    $ret_val .= "removed $count existing $assigned_by annotations\n";
  }

  return $ret_val;
}
