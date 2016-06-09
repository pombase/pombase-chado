package PomBase::Retrieve::GOPhysicalInteractions;

=head1 NAME

PomBase::Retrieve::GOPhysicalInteractions - Exporter for a simple file of GO
                                            physical interactions (GO:0005515)

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Retrieve::GOPhysicalInteractions

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;
use Moose;

use List::Gen 'iterate';

use PomBase::Retrieve::GeneAssociationFile;

with 'PomBase::Role::ConfigUser';
with 'PomBase::Role::ChadoUser';
with 'PomBase::Role::DbQuery';
with 'PomBase::Role::CvQuery';
with 'PomBase::Role::OrganismFinder';
with 'PomBase::Retriever';

has gaf_retriever => (is => 'rw', init_arg => undef,
                     lazy_build => 1);

method _build_gaf_retriever {
  my @options = @{$self->options()};

  push @options, '--filter-by-term=GO:0005515';

  return
    PomBase::Retrieve::GeneAssociationFile->new(chado => $self->chado(),
                                                config => $self->config(),
                                                options => \@options);
}

method retrieve() {
  my $retriever = $self->gaf_retriever();
  my $results = $retriever->retrieve();

  my $seen_rows = {};

  # used as a temporary storage when a "with" has more than one ID separated by
  # pipes
  my $left_over_split_row = undef;

  my $it = do {
    iterate {
    ROW:
      {
        my $row = $left_over_split_row // $results->next();

        $left_over_split_row = undef;

        if ($row) {
          my ($gene_identifier, $with_identifier, $pub_uniquename,
              $evidence_code) =
            ($row->[1], $row->[7]->trim(), $row->[5], $row->[6]);

          if ($evidence_code ne 'IPI') {
            goto ROW;
          }

          if ($with_identifier->length() == 0) {
            goto ROW;
          } else {
            if ($with_identifier =~ /^UniProt/) {
              warn "Not exporting GO physical interaction that has a UniProt " .
                "ID ($with_identifier) as the with field.  This ID need to " .
                "be added to: " .
                $self->config()->{pombase_to_uniprot_mapping} . "\n";
              goto ROW;
            }
          }

          if ($with_identifier =~ /^GO:/) {
            goto ROW;
          }

          my @withs = split /\|/, $with_identifier;

          if (@withs > 1) {
            $with_identifier = shift @withs;
            $left_over_split_row = [@$row];
            $left_over_split_row->[7] = join '|', @withs
          }

          my $database_name = $self->config()->{database_name};

          $with_identifier =~ s/^$database_name://;

          my $key = "$gene_identifier - $with_identifier - $pub_uniquename";

          if ($seen_rows->{$key}) {
            goto ROW;
          }

          $seen_rows->{$key} = 1;

          return [$gene_identifier, $with_identifier, $pub_uniquename];
        } else {
          return undef;
        }
      }
    };
  }
};

method header () {
  # no header
  return '';
}

method format_result($res) {
  return (join "\t", @$res);
}
