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
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::FeatureFinder';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Role::XrefStorer';
with 'PomBase::Role::CvtermCreator';
with 'PomBase::Role::FeatureCvtermCreator';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);
has assigned_by_filter => (is => 'rw', init_arg => undef);
has remove_existing => (is => 'rw', init_arg => undef);
has with_filter_values => (is => 'rw', isa => 'HashRef',
                             init_arg => undef);
has term_id_filter_values => (is => 'rw', isa => 'HashRef',
                              init_arg => undef);

method _load_first_column($filename)
{
  my %ret_val = ();

  open my $file, '<', $filename
    or die "can't open $filename: $!\n";

  while (defined (my $line = <$file>)) {
    if ($line =~ /^(\S+)/ and length $1 > 0) {
      $ret_val{$1} = 1;
    } else {
      warn "line has no first column: $line";
    }
  }

  close $file or die "$!";

  return %ret_val;
}

method BUILD
{
  my $assigned_by_filter = '';
  my $remove_existing = 0;
  my $with_filter_filename = undef;
  my $term_id_filter_filename = undef;

  my @opt_config = ('assigned-by-filter=s' => \$assigned_by_filter,
                    'remove-existing' => \$remove_existing,
                    'with-filter-filename=s' =>
                      \$with_filter_filename,
                    'term-id-filter-filename=s' =>
                      \$term_id_filter_filename);
  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  $assigned_by_filter =~ s/^\s+//;
  $assigned_by_filter =~ s/\s+$//;

  if (length $assigned_by_filter == 0) {
    die "no assigned-by-filter option given - no annotation will " .
      "be loaded\n";
  }

  $self->assigned_by_filter([split /\s*,\s*/, $assigned_by_filter]);
  $self->remove_existing($remove_existing);

  my %with_filter_values =
    $self->_load_first_column($with_filter_filename);
  $self->with_filter_values({%with_filter_values});

  my %term_id_filter_values =
    $self->_load_first_column($term_id_filter_filename);
  $self->term_id_filter_values({%term_id_filter_values});
}

method load($fh)
{
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

  my $csv = Text::CSV->new({ sep_char => "\t" });

  $csv->column_names(qw(DB DB_object_id DB_object_symbol Qualifier GO_id DB_reference Evidence_code With_or_from Aspect DB_object_name DB_object_synonym DB_object_type Taxon Date Assigned_by Annotation_extension Gene_product_form_id ));

  my %with_filter = %{$self->with_filter_values()};
  my %term_id_filter = %{$self->term_id_filter_values()};

  while (my $columns_ref = $csv->getline_hr($fh)) {
    my $db_object_id = $columns_ref->{"DB_object_id"};
    my $db_object_symbol = $columns_ref->{"DB_object_symbol"};
    my $qualifier = $columns_ref->{"Qualifier"};

    die "annotation with multiple qualifiers ($qualifier)\n"
      if $qualifier =~ /\|/;

    my $is_not = 0;

    if ($qualifier =~ /^not$/i) {
      $is_not = 1;
    }

    my $go_id = $columns_ref->{"GO_id"};

    if ($term_id_filter{$go_id}) {
      next;
    }

    my $db_reference = $columns_ref->{"DB_reference"};

    my $evidence_code = $columns_ref->{"Evidence_code"};
    my $long_evidence =
      $self->config()->{evidence_types}->{$evidence_code}->{name};

    my $with_or_from = $columns_ref->{"With_or_from"};

    if ($with_filter{$with_or_from}) {
      next;
    }

    my $db_object_synonym = $columns_ref->{"DB_object_synonym"};
    (my $taxonid = $columns_ref->{"Taxon"}) =~ s/taxon://i;

    my $new_taxonid = $config->{organism_taxon_map}->{$taxonid};
    if (defined $new_taxonid) {
      $taxonid = $new_taxonid;
    }

    my $date = $columns_ref->{"Date"};
    my $assigned_by = $columns_ref->{"Assigned_by"};

    next unless $assigned_by_filter{$assigned_by};

    my @synonyms = split /\|/, $db_object_synonym;

    push @synonyms, $db_object_id, $db_object_symbol;

    my $uniquename_re = $config->{systematic_id_re};
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
        } catch {
          warn "$_";
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

      my $feature_cvterm =
        $self->create_feature_cvterm($feature, $cvterm, $pub, $is_not);

      $self->add_feature_cvtermprop($feature_cvterm, 'assigned_by',
                                    $assigned_by);

      $self->add_feature_cvtermprop($feature_cvterm, 'evidence',
                                    $long_evidence);
    };

    try {
      $chado->txn_do($proc);
    } catch {
      warn "Failed to load row: $_\n";
    }
  }

  return \%deleted_counts;
}

method results_summary($results)
{
  my $ret_val = '';

  for my $assigned_by (sort keys %$results) {
    my $count = $results->{$assigned_by};
    $ret_val .= "removed $count existing $assigned_by annotations\n";
  }

  return $ret_val;
}
