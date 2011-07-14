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

func _load_genes($chado, $organism, $test_mode) {
  my $gene_type = $chado->resultset('Cv::Cvterm')->find({ name => 'gene' });
  my $org_name = $organism->genus() . ' ' . $organism->species();
  my @res;

  my $file_name = $organism->species() . "_genes";

  if (-e $file_name) {
    warn "loading from cache file: $file_name\n";
    @res = LoadFile($file_name);
  } else {
    warn "getting gene information via InterMine API for $org_name\n";
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

    last if $test_mode and scalar(keys %seen_names) >= 3;
  }

  warn "loaded ", scalar(keys %seen_names), " genes for $org_name\n";
}

func _load_cvterms($chado, $config)
{
  my $db_name = 'PomBase';
  my $db = $chado->resultset('General::Db')->find({ name => $db_name });

  my %cv_confs = %{$config->{cvs}};

  my %cvs = ();

  for my $cv_name (keys %cv_confs) {
    my $cv;

    if (exists $cvs{$cv_name}) {
      $cv = $cvs{$cv_name};
    } else {
      $cv = $chado->resultset('Cv::Cv')->find_or_create({ name => $cv_name });
      $cvs{$cv_name} = $cv;
    }

    my @cvterm_confs = @{$cv_confs{$cv_name}};

    for my $cvterm_conf (@cvterm_confs) {
      my $cvterm_name;
      my $cvterm_definition;

      if (ref $cvterm_conf) {
        $cvterm_name = $cvterm_conf->{name};
        $cvterm_definition = $cvterm_conf->{definition};
      } else {
        $cvterm_name = $cvterm_conf;
      }

      $cvterm_name =~ s/ /_/g;

      my $accession = $config->{id_counter}->get_dbxref_id($db_name);
      my $formatted_accession = sprintf "%07d", $accession;

      my $dbxref =
        $chado->resultset('General::Dbxref')->create({
          db_id => $db->db_id(),
          accession => $formatted_accession,
        });

      $chado->resultset('Cv::Cvterm')
        ->find_or_create({ name => $cvterm_name,
                           cv_id => $cv->cv_id(),
                           dbxref_id => $dbxref->dbxref_id(),
                           definition => $cvterm_definition,
                         });
    }
  }
}

func _load_dbs($chado, $config)
{
  my @dbs = @{$config->{dbs}};

  for my $db (@dbs) {
    $chado->resultset('General::Db')->find_or_create({ name => $db });
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

  _load_genes($chado, $human, $config->{test_mode});
  _load_genes($chado, $scerevisiae, $config->{test_mode});

  _load_cvterms($chado, $config);
  _load_dbs($chado, $config);

  return $pombe_org;
}

1;
