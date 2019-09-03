#!/usr/bin/env perl
use Git::Hooks;
use Data::Dumper qw/Dumper/;
use IO::Socket;
use IO::Select;
use Storable qw/nstore_fd/;

my $message = "";
COMMIT_MSG  {
    my $git = shift;
    my $socket = IO::Socket::INET->new(
        PeerAddr    => 'localhost',
        PeerPort    =>  2808,
        Proto       => 'tcp',
        Timeout     =>  1
    )
        or die "Could not connect";
    
    
    my @status =  $git->run(qw/status/);
    print Dumper $git; 
     
    my $message = readFile(shift);
    my $rep = $git->{work_tree};
    $rep =~ s/.+\/(.+)/$1/g;
    my $hash = {Repertoire => $rep, action => {ajout =>[] , sup=>[], mod=>[], rename=>[]}, commitMessage=> $message};
    foreach my $line (@status)
    {
        if ($line =~ /nouveau fichier.+:\s+(.+)/)
        {
            push @{$hash->{action}->{ajout}}, $1;
        }
        elsif ($line =~ /supprimé.+:\s+(.+)/)
        {
            push @{$hash->{action}->{sup}}, $1;
        }
        elsif ($line =~ /modifié.+:\s+(.+)/)
        {
            push @{$hash->{action}->{mod}}, $1;
        }
        elsif($line =~ /renomé.+:\s+(.+)/)
        {
            push @{$hash->{action}->{rename}}, $1;
        }
    }
      nstore_fd $hash, $socket;
};
POST_COMMIT {
    $message .= "jai fini de commit \n";
    open(my $file,'>','/tmp/hook') or die $!;
    print $file Dumper @_;
};

sub readFile  {
    my $file = shift;
    open(my $files,'<',$file) or die $!;
    my $buffer ="";
    while (<$files>)
    {
        $buffer = $_;
    }
    return $buffer;
}
sub check_new_files {
    my ($git, $commit, @files) = @_;

    my $errors = 0;

    foreach ($git->run(qw/ls-files -s/, @files)) {
        my ($mode, $sha, $n, $name) = split ' ';
        my $size = $git->file_size(":0:$name");
        if ($size > $limit) {
            $git->fault("File '$name' has $size bytes, more than our limit of $limit",
                {prefix => 'CheckSize', commit => $commit});
            ++$errors;
        }
    }

    return $errors == 0;
}

run_hook($0, @ARGV);
