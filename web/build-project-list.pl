#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use LWP::Simple;
use JSON;
use YAML qw (Load LoadFile);
use HTML::Template;
use Web::Scraper;

my $output_dir = shift(@ARGV) || './';

local $| = 1;
my $stats = { success => 0, failed => 0, errors => [] };

my $list_url = 'http://github.com/masak/proto/raw/master/projects.list';

my $site_info = {
    'github' => {
        url => sub {
            my $project = shift;
            return "http://github.com/$project->{owner}/$project->{name}/";
        },
        scraper => scraper {
            process 'id("repository_description")/p/text()', description => 'TEXT';
        },
    },
    'gitorious' => {
        url => sub {
            my $project = shift;
            return "http://gitorious.org/$project->{name}/";
        },
        scraper => scraper {
            process 'id("project-description")/p/text()', description => 'TEXT';
        },
    },
};

my $projects = get_projects($list_url);

print "ok - $stats->{success}\nnok - $stats->{failed}\n";
print STDERR join '', @{ $stats->{errors} } if $stats->{errors};

die "Too many errors no output generated"
  if $stats->{failed} > $stats->{success};

spew( $output_dir . 'index.html', get_html_list($projects) );
spew( $output_dir . 'proto.json', get_json($projects) );

print "index.html and proto.json files generated\n";

sub spew {
    open( my $fh, ">", shift ) or return -1;
    print $fh @_;
    close $fh;
    return;
}    #spew ($filename,$data) ... saves $data in $filename.

sub get_projects {
    my ($list_url) = @_;
    my $projects = Load( get($list_url) );
    foreach my $project_name ( keys %$projects ) {
        my $project = $projects->{$project_name};
        $project->{name} = $project_name;
        print "$project_name\n";
        if ( !$project->{home} ) {
            delete $projects->{$project_name};
            next;
        }

        my $home = $site_info->{ $project->{home} };
        if ( !$home ) {
            delete $projects->{$project_name};
            $stats->{failed}++;
            push @{ $stats->{errors} },
                "Don't know how to get info for $project->{name} from $project->{home} (new repository?) \n";
            next;
        }

        $project->{url} = $home->{url}->($project);

        if ( my $result = $home->{scraper}->scrape ( get ( $project->{url} ) ) ) {
            if ( my $desc = $result->{description} ) {
                $desc =~ s/^\s+//;
                $desc =~ s/\s+$//;

                $project->{description} = $desc;

                $stats->{success}++;
            }
            else {
                delete $projects->{$project_name};
                $stats->{failed}++;
                push @{ $stats->{errors} },
                    "Could not get a description for $project->{name} from $project->{url}, that's BAD!\n";
                $project->{description} = '';
            }

            print "$project->{description}\n\n";
        }
        else {
           delete $projects->{$project_name};
           $stats->{failed}++;
           push @{ $stats->{errors} },
               "Error for project $project->{name} : could not get $project->{url} (project probably dead)\n";
           next;
        }
    }
    return $projects;
}

sub get_html_list {
    my ($projects) = @_;
    my $li;
    my $template = HTML::Template->new(
        filename          => 'index.tmpl',
        die_on_bad_params => 0,
        default_escape    => 'html',
    );

    my @projects = map { $projects->{$_} }
      sort { lc($a) cmp lc($b) } keys %$projects;
    $template->param( projects => \@projects );
    return $template->output;
}

sub get_json {
    my ($projects) = @_;
    my $json = encode_json($projects);

    #$json =~ s/},/},\n/g;
    return $json;
}
