package PomBase::Check::AlleleNotStartingWithGeneName;

=head1 NAME

PomBase::Check::AlleleNotStartingWithGeneName - Make sure that all allele names
                                                start with a gene name

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Check::AlleleNotStartingWithGeneName

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2013 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use warnings;
use Carp;
use Moose;

with 'PomBase::Checker';

sub description {
  return "Check that all allele names start with a gene name or gene synonym";
}

my @known_ok_names = ('xlf1.EE(T180E,S192E)',
                      qw(
                          srp7.1
                          hus5.62
                          xlf1.AA
                          rad15.P
                          hus5.17
                          sad1.2
                          brr6.ts8
                          sad1.1
                          rad26.a14
                          cut12.s11
                          ade8.106
                          ade7.50
                          rad50S
                          hsp-tev-2
                          ppk8'-1
                          ppk8'-3
                          ppk8'-7
                          ppk8'-8
                          ppk8'-4
                          ppk8'-2
                          ppk8'-5
                          ppk8'-6
                          res1'-5
                          res1'-2
                          res1'-3
                          res1'-4
                          res1'-7
                          res1'-6
                          res1'-8
                          res1'-10
                          res1'-11
                          res1'-12
                          res1'-13
                          res1'-2A
                          res1'-2B
                          res1'-B
                          res1'-2D
                          res1'-2C
                          res1'-D
                          res1'-2E
                          res1'-E
                      ));

sub check {
  my $self = shift;

  my $chado = $self->chado();

  my $synonym_query = <<"EOQ";
       SELECT gene.uniquename,
              s.name
       FROM feature gene
       JOIN feature_synonym fs ON gene.feature_id = fs.feature_id
       JOIN SYNONYM s ON s.synonym_id = fs.synonym_id
       JOIN cvterm t ON gene.type_id = t.cvterm_id
       WHERE t.name = 'gene';
EOQ

  my $dbh = $chado->storage()->dbh();
  my $sth = $dbh->prepare($synonym_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my %gene_synonyms = ();

  while (my ($gene_uniquename, $synonym) = $sth->fetchrow_array()) {
    push @{$gene_synonyms{$gene_uniquename}}, $synonym;
  }

  my $allele_name_query = <<"EOQ";
        SELECT allele.name AS allele_name,
               gene.name AS gene_name,
               gene.uniquename AS gene_uniquename,
               array_to_string(array
                                 (SELECT DISTINCT value
                                  FROM featureprop p
                                  WHERE p.feature_id = allele.feature_id
                                    AND p.type_id in
                                      (SELECT cvterm_id
                                       FROM cvterm
                                       WHERE name = 'canto_session')), ',') AS canto_session
        FROM feature allele
        JOIN feature_relationship rel ON rel.subject_id = allele.feature_id
        JOIN cvterm rel_type ON rel.type_id = rel_type.cvterm_id
        JOIN feature gene ON rel.object_id = gene.feature_id
        JOIN cvterm allele_type ON allele_type.cvterm_id = allele.type_id
        WHERE rel_type.name = 'instance_of'
          AND allele_type.name = 'allele'
          AND allele.feature_id NOT IN
             (SELECT feature_id FROM featureprop fp
                                JOIN cvterm fpt ON fpt.cvterm_id = fp.type_id
               WHERE fpt.name = 'allele_type' AND fp.value = 'fusion_or_chimera')
          AND allele.name IS NOT NULL;
EOQ

  $dbh = $chado->storage()->dbh();
  $sth = $dbh->prepare($allele_name_query);
  $sth->execute() or die "Couldn't execute: " . $sth->errstr;

  my $output_text = '';
  my $count = 0;

  my @gene_tags = qw|GST GFP EGFP nmt1 nmt41 nmt81 NLS NES TetR|;
  my $gene_tags_re = '(?:' . (join "|", @gene_tags) . ')-';

  my $re = qr/(\(|delta([\-\(a-zA-Z\d]|::)|delta$|\+$|-|::)/;

 ROW:
  while (my ($allele_name, $gene_name, $gene_uniquename, $canto_session) = $sth->fetchrow_array()) {
    if (!$gene_name) {
      next;
    }

    if ($allele_name =~ /^(?:(?:$gene_tags_re)?$gene_name$re|$gene_tags_re$gene_name)/) {
      next;
    }

    if (grep { $_ eq $allele_name } @known_ok_names) {
      next;
    }

    my @gene_synonyms = @{$gene_synonyms{$gene_uniquename} // []};;

    for my $gene_synonym (@gene_synonyms) {
      if ($allele_name =~ /^(?:(?:$gene_tags_re)?$gene_synonym$re|$gene_tags_re$gene_name)/) {
        next ROW;
      }
    }

    $output_text .= "$allele_name\t$gene_name\t$gene_uniquename\t$canto_session\n";

    $count++;
  }

  $self->output_text($output_text);

  return $count == 0;
}


1;
