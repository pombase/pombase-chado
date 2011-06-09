package PomBase::Load;

=head1 NAME

PomBase::Load - Code for initialising and loading data into the PomBase Chado
                database

=head1 SYNOPSIS

=head1 AUTHOR

Kim Rutherford C<< <kmr44@cam.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<kmr44@cam.ac.uk>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PomBase::Load

=over 4

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Kim Rutherford, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use perl5i::2;

use PomBase::External;
use PomBase::Chado::LoadOrganism;

use YAML::Any qw(DumpFile LoadFile);

func _load_genes($chado, $organism) {
  my $gene_type = $chado->resultset('Cv::Cvterm')->find({ name => 'gene' });
  my $org_name = $organism->genus() . ' ' . $organism->species();
  my @res;

  my $file_name = $organism->species() . "_genes";

  if (-e $file_name) {
    print "loading from cache file: $file_name\n";
    @res = LoadFile($file_name);
  } else {
    @res = PomBase::External::get_genes($org_name);
    DumpFile($file_name, @res);
  }

  my %seen_names = ();

  my $count = 0;

  for my $gene (@res) {
    my $primary_identifier = $gene->{primary_identifier};

    my $name;

    if ($org_name eq 'Saccharomyces cerevisiae') {
      $name = $gene->{secondary_identifier};
    } else {
      $name = $gene->{symbol};
    }

    if (defined $name and length $name > 0) {
      if (exists $seen_names{lc $name}) {
        croak "seen name twice: $name(from $primary_identifier) and from "
          . $seen_names{lc $name};
      }
    } else {
      $name = $primary_identifier;
    }

    $seen_names{lc $name} = $primary_identifier;

    $chado->resultset('Sequence::Feature')->create({
      uniquename => $primary_identifier,
      name => $name,
      organism_id => $organism->organism_id(),
      type_id => $gene_type->cvterm_id()
    });

#    last if scalar(keys %seen_names) >= 2;
  }

  print "loaded ", scalar(keys %seen_names), " genes for $org_name\n";
}

func _load_cvterms($chado, $config)
{
  my $db = $chado->resultset('General::Db')->find({ name => 'PomBase' });

  my %cvterm_confs = %{$config->{cvterms}};

  my %cvs = ();

  for my $cv_name (keys %cvterm_confs) {
    my @cvterm_names = @{$cvterm_confs{$cv_name}};

    for my $cvterm_name (@cvterm_names) {
      my $dbxref =
        $chado->resultset('General::Dbxref')->create({
          db_id => $db->db_id(),
          accession => $cvterm_name,
        });

      my $cv;

      if (exists $cvs{$cv_name}) {
        $cv = $cvs{$cv_name};
      } else {
        $cv = $chado->resultset('Cv::Cv')->create({ name => $cv_name });
        $cvs{$cv_name} = $cv;
      }

      $chado->resultset('Cv::Cvterm')->create({ name => $cvterm_name,
                                                cv_id => $cv->cv_id(),
                                                dbxref_id => $dbxref->dbxref_id()
                                              });
    }
  }
}

func _load_dbs($chado, $config)
{
  my @dbs = @{$config->{dbs}};

  for my $db (@dbs) {
    $chado->resultset('General::Db')->create({ name => $db });
  }
}

func init_objects($chado, $config) {
  my $org_load = PomBase::Chado::LoadOrganism->new(chado => $chado);

  my $pombe_org =
    $org_load->load_organism("Schizosaccharomyces", "pombe", "pombe",
                             "Spombe", 4896);


  my $human =
    $org_load->load_organism('Homo', 'sapiens', 'human', 'human', 9606);

  my $scerevisiae =
    $org_load->load_organism('Saccharomyces', 'cerevisiae', 'Scerevisiae',
                             'Scerevisiae', 4932);

  _load_genes($chado, $human);
  _load_genes($chado, $scerevisiae);

  _load_cvterms($chado, $config);
  _load_dbs($chado, $config);

  return $pombe_org;
}

1;
