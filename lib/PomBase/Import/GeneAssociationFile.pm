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

use strict;
use warnings;
use Carp;

use Try::Tiny;
use Capture::Tiny qw(capture);

use IO::Handle;

use Moose;

use Text::CSV;
use Getopt::Long qw(GetOptionsFromArray);

use PomBase::Chado::ExtensionProcessor;

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
with 'PomBase::Role::GOAnnotationProperties';

with 'PomBase::Importer';

has verbose => (is => 'ro');
has options => (is => 'ro', isa => 'ArrayRef', required => 1);
has assigned_by_filter => (is => 'rw', init_arg => undef);
has verbose_assigned_by_filter => (is => 'rw', init_arg => undef);
has taxon_filter => (is => 'rw', init_arg => undef);
has remove_existing => (is => 'rw', init_arg => undef);
has use_first_with_id => (is => 'rw', init_arg => undef);
has ignore_synonyms => (is => 'rw', init_arg => undef);
has load_qualifiers => (is => 'rw', init_arg => undef);
has load_column_17 => (is => 'rw', init_arg => undef);
has with_prefix_filter => (is => 'rw', init_arg => undef);
has with_filter_values => (is => 'rw', isa => 'HashRef',
                             init_arg => undef);
has term_id_filter_values => (is => 'rw', isa => 'HashRef',
                              init_arg => undef);

has extension_processor => (is => 'ro', init_arg => undef, lazy_build => 1);

sub _build_extension_processor {
  my $self = shift;
  my $processor = PomBase::Chado::ExtensionProcessor->new(chado => $self->chado(),
                                                          config => $self->config(),
                                                          pre_init_cache => 1,
                                                          verbose => $self->verbose());
  return $processor;
}

sub _load_first_column {
  my $self = shift;
  my $filename = shift;

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

sub BUILD {
  my $self = shift;
  my $assigned_by_filter = '';
  my $verbose_assigned_by_filter = '';
  my $taxon_filter = '';
  my $remove_existing = 0;
  my $with_filter_filename = undef;
  my $term_id_filter_filename = undef;
  my $with_prefix_filter = undef;

  # if true only the first ID from a with field will be stored
  my $use_first_with_id = 0;

  # if true, don't try to look up the gene using the synonyms column values
  my $ignore_synonyms = 0;

  my $load_qualifiers = 0;
  my $load_column_17 = 0;

  my @opt_config = ('assigned-by-filter=s' => \$assigned_by_filter,
                    'verbose-assigned-by-filter=s' => \$verbose_assigned_by_filter,
                    'remove-existing' => \$remove_existing,
                    'taxon-filter=s' => \$taxon_filter,
                    'with-filter-filename=s' =>
                      \$with_filter_filename,
                    'term-id-filter-filename=s' =>
                      \$term_id_filter_filename,
                    'with-prefix-filter' => \$with_prefix_filter,
                    'use-only-first-with-id' => \$use_first_with_id,
                    'ignore-synonyms' => \$ignore_synonyms,
                    'load-qualifiers' => \$load_qualifiers,
                    'load-column-17' => \$load_column_17,
                  );

  if (!GetOptionsFromArray($self->options(), @opt_config)) {
    croak "option parsing failed";
  }

  $assigned_by_filter =~ s/^\s+//;
  $assigned_by_filter =~ s/\s+$//;

  if (length $taxon_filter == 0) {
    warn "notice: no taxon filter - annotation will be loaded for all taxa\n";
  }

  $self->assigned_by_filter([split /\s*,\s*/, $assigned_by_filter]);
  $self->verbose_assigned_by_filter($verbose_assigned_by_filter);
  $self->taxon_filter([split /\s*,\s*/, $taxon_filter]);
  $self->remove_existing($remove_existing);

  my %with_filter_values =
    $self->_load_first_column($with_filter_filename);
  $self->with_filter_values({%with_filter_values});

  my %term_id_filter_values =
    $self->_load_first_column($term_id_filter_filename);
  $self->term_id_filter_values({%term_id_filter_values});

  $self->use_first_with_id($use_first_with_id);
  $self->ignore_synonyms($ignore_synonyms);

  $self->load_qualifiers($load_qualifiers);
  $self->load_column_17($load_column_17);

  $self->with_prefix_filter($with_prefix_filter);
}

sub load {
  my $self = shift;
  my $fh = shift;

  my $file_name = $self->file_name_of_fh($fh);

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

  my $with_prefix_filter = $self->with_prefix_filter();

  my $uniquename_re = $config->{systematic_id_re};

  if (!defined $uniquename_re) {
    die "systematic_id_re configuration variable not set\n";
  }

 LINE:
  while (defined (my $line = $fh->getline())) {
    next if $line =~ /^\s*!/;

    if (!$csv->parse($line)) {
      die "line $.: Parse error: ", $csv->error_input(), "\n";
    }

    if (scalar($csv->fields()) < 14) {
      warn "line ", $fh->input_line_number(), ": not enough fields - skipping\n";
      next;
    }

    my %columns = ();

    @columns{ $csv->column_names() } = map {
      s/^\s+//;
      s/\s+$//;
      $_;
    } $csv->fields();

    my $taxonid = $columns{"Taxon"};

    if (!defined $taxonid) {
      warn "line ", $fh->input_line_number(), ": taxon missing - skipping\n";
      next;
    }

    $taxonid =~ s/taxon://ig;

    if ($taxonid !~ /^\d+$/) {
      warn "line ", $fh->input_line_number(), ": taxon is not a number - skipping\n";
      next;
    }

    my $new_taxonid = $config->{organism_taxon_map}->{$taxonid};
    if (defined $new_taxonid) {
      $taxonid = $new_taxonid;
    }

    my @taxon_filter = @{$self->taxon_filter()};

    if (@taxon_filter > 0 && !grep { $_ == $taxonid; } @taxon_filter) {
      warn "line ", $fh->input_line_number(), ": skipping, wrong taxon: $taxonid\n" if $self->verbose();
      next;
    }

    my $db_object_id = $columns{"DB_object_id"};
    my $db_object_symbol = $columns{"DB_object_symbol"};
    my $qualifier = $columns{"Qualifier"};

    my $is_not = 0;

    my @qualifier_bits = split /\|/, $qualifier;

    if (@qualifier_bits > 0) {
      @qualifier_bits = map {
        my $qual = $_;
        if ($qual =~ /^not$/i) {
          $is_not = 1;
          ();
        } else {
          $qual;
        }
      } @qualifier_bits;
    }

    if (@qualifier_bits > 1) {
      warn "line ", $fh->input_line_number(), ": annotation with multiple qualifiers ($qualifier) - skipping\n";
      next;
    }

    my $go_id = $columns{"GO_id"};

    if ($go_id =~ /^s*$/) {
      warn "line ", $fh->input_line_number(), ": GO ID missing - skipping\n";
      next;
    }

    if ($go_id !~ /^GO:\d\d\d\d\d\d\d$/) {
      warn "line ", $fh->input_line_number(),
        ": text doesn't look like a GO ID: $go_id - skipping\n";
      next;
    }

    if ($term_id_filter{$go_id}) {
      if ($self->verbose()) {
        warn "line ", $fh->input_line_number(),
          ": ignoring because of term filter: $go_id\n";
      }
      next;
    }

    my $db_references = $columns{"DB_reference"};

    my $evidence_code = $columns{"Evidence_code"};
    my $long_evidence =
      $self->config()->{evidence_types}->{$evidence_code}->{name};

    my $with_or_from_column = $columns{"With_or_from"};
    my @withs_and_froms = ();

    if (length $with_or_from_column > 0) {
      if ($evidence_code eq 'IC') {
        @withs_and_froms = grep {
          if (/\|/) {
            warn qq{ignoring $evidence_code from value containing a pipe ("|") at line $.: $_\n};
            0;
          } else {
            1;
          }
        } split (/,/, $with_or_from_column);
      } else {
        # we treat pipe as if they were commas for with fields because
        # it amounts to the same thing
        @withs_and_froms = split (/,|\|/, $with_or_from_column);
      }
    }

    if (defined $with_prefix_filter) {
      @withs_and_froms = grep { /^$with_prefix_filter/ } @withs_and_froms;
    }

    for (my $i = 0; $i < @withs_and_froms; $i++) {
      my $with_or_from = $withs_and_froms[$i];

      if ($with_filter{$with_or_from}) {
        if ($self->verbose()) {
          warn "ignoring line because of with filter: $with_or_from\n";
        }
        next LINE;
      }

      if ($with_or_from !~ /:/) {
        warn "line ", $fh->input_line_number(),
          ": with/from value has no DB prefix: $with_or_from - skipping\n";
        next LINE;
      }

      my $local_id = $self->lookup_uniprot_id($with_or_from);

      if (defined $local_id) {
        $withs_and_froms[$i] = $local_id;
      } else {
        if ($with_or_from =~ /^UniProtKB:/ && $go_id eq 'GO:0005515') {
          # with field contains a non-pombe gene
          next LINE;
        }
      }
    }

    my $db_object_synonym = $columns{"DB_object_synonym"};

    my $date = $columns{"Date"};

    if ($date =~ /^\s*$/) {
      warn "line ", $fh->input_line_number(), ": date missing - skipping\n";
      next;
    }

    if ($date !~ /^\d\d\d\d-?\d\d-?\d\d$/) {
      warn "line ", $fh->input_line_number(), ": date not in YYYY-MM-DD(ISO) or YYYMMDD format: $date - skipping\n";
      next;
    }

    my $assigned_by = $columns{"Assigned_by"};

    if (!defined $assigned_by || $assigned_by =~ /^\s*$/) {
      warn "line ", $fh->input_line_number(), ": assigned by missing - skipping\n";
      next;
    }

    if (@assigned_by_filter && !$assigned_by_filter{$assigned_by}) {
      if ($self->verbose() || $self->verbose_assigned_by_filter()) {
        warn "line ", $fh->input_line_number(),
          ": ignoring because this value does match the assigned_by filter: $assigned_by\n";
      }
      next;
    }

    my @synonyms = ();

    if (!$self->ignore_synonyms()) {
      @synonyms = split /\|/, $db_object_synonym;
    }

    push @synonyms, $db_object_id, $db_object_symbol;

    map { s/\s+$//; s/^\s+//; } @synonyms;

    my $uniquename = undef;

    my $organism = $self->find_organism_by_taxonid($taxonid);

    if (!defined $organism) {
      warn "ignoring annotation for organism $taxonid\n";
      next;
    }

    my $gene_feature;
    # try systematic ID first
    for my $synonym (@synonyms) {
      if ($synonym =~ /^($uniquename_re)/) {
        try {
          $gene_feature = $self->find_chado_feature("$synonym", 1, 1, $organism);
        };

        last if defined $gene_feature;
      }
    }

    if (!defined $gene_feature) {
      for my $synonym (@synonyms) {
        try {
          $gene_feature = $self->find_chado_feature("$synonym", 1, 1, $organism);
        } catch {
          # feature not found
        };

        last if defined $gene_feature;
      }
    }

    if (!defined $gene_feature) {
      warn "line ", $fh->input_line_number(), ": gene feature not found, ",
        "none of the identifiers (@synonyms) from this annotation ",
        "match a systematic ID in Chado - skipping\n";
      next;
    }

    for my $feature ($self->get_transcripts_of_gene($gene_feature)) {

      my @pubs = map {
        my $db_reference = $_;
        $self->find_or_create_pub($db_reference);
      } split /\|/, $db_references;

      map {
        my $pub = $_;
      } @pubs;

      my $proc = sub {
        my $cvterm = $self->find_cvterm_by_term_id($go_id);

        if (!defined $cvterm) {
          warn "line ", $fh->input_line_number(), ": can't load annotation, $go_id not found in database\n";
          return;
        }

        my $extension_text = $columns{"Annotation_extension"};

        my @extension_split;

        if (defined $extension_text && length $extension_text > 0) {
          @extension_split = sort split /(?<=\))\|/, $extension_text;
        } else {
          @extension_split = ("");
        }

        for my $extension_split_text (@extension_split) {
        my $feature_cvterm =
          $self->create_feature_cvterm($feature, $cvterm, $pubs[0], $is_not);

        if (@pubs > 1) {
          warn "ignored ", (@pubs - 1), " extra refs for ", $feature->uniquename(), "\n";
        }

        if ($extension_split_text) {
          my $err = undef;

          my $processor = $self->extension_processor();

          try {
            $processor->process_one_annotation($feature_cvterm, $extension_split_text);
          } catch {
            chomp $_;
            $err = $_;
          };

          if ($err) {
            warn "line $.: $err\n";
            $feature_cvterm->delete();
            return;
          }
        }

        $self->add_feature_cvtermprop($feature_cvterm, 'assigned_by',
                                      $assigned_by);
        $self->add_feature_cvtermprop($feature_cvterm, 'date', $date);
        $self->add_feature_cvtermprop($feature_cvterm, 'evidence',
                                      $long_evidence);

        if ($self->load_qualifiers()) {
          for my $qual (@qualifier_bits) {
            $self->add_feature_cvtermprop($feature_cvterm, 'qualifier',
                                          $qual);
          }
        }

        if ($self->load_column_17()) {
          my $col_17_value = $columns{"Gene_product_form_id"};

          if ($col_17_value) {
            $self->add_feature_cvtermprop($feature_cvterm, 'gene_product_form_id',
                                          $col_17_value);
          }
        }

        my $annotation_throughput_type = $self->annotation_throughput_type($evidence_code);
        if ($annotation_throughput_type) {
          $self->add_feature_cvtermprop($feature_cvterm, 'annotation_throughput_type',
                                        $annotation_throughput_type);
        }

        for (my $i = 0; $i < @withs_and_froms; $i++) {
          my $with_or_from = $withs_and_froms[$i];

          if ($use_first_with_id && $i > 0) {
            next;
          }

          $self->add_feature_cvtermprop($feature_cvterm, 'with',
                                        $with_or_from, $i);
        }

        if (defined $file_name) {
          $self->add_feature_cvtermprop($feature_cvterm, 'source_file',
                                        $file_name);
        }

        }

      };

      try {
        $chado->txn_do($proc);
      }
      catch {
        warn "line ", $fh->input_line_number(), ": ($_)\n";
      }
    }
  }

  if (!$csv->eof()){
    $csv->error_diag();
  }

  return \%deleted_counts;
}

sub results_summary {
  my $self = shift;
  my $results = shift;

  my $ret_val = '';

  for my $assigned_by (sort keys %$results) {
    my $count = $results->{$assigned_by};
    $ret_val .= "removed $count existing $assigned_by annotations\n";
  }

  return $ret_val;
}

1;
