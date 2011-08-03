package MogileFS::REST;
use Dancer ':syntax';
use Carp;
use HTTP::Status ':constants';
use MogileFS::Client;
use Data::Dumper;

our $VERSION = '0.1';

my $mogservers;
if (my $cnf = $ENV{MOGILEFS_REST_SERVERS}) {
    $mogservers = [  split /,/, $cnf ];
}
$mogservers ||= config->{servers};
my $mogdomain = $ENV{MOGILEFS_REST_DOMAIN} || config->{domain};
my $mogclass = $ENV{MOGILEFS_REST_CLASS} || config->{class};

my $client = MogileFS::Client->new(
    domain => $mogdomain,
    hosts  => $mogservers,
);

debug("Mogile config: " . (Dumper [$mogservers, $mogdomain, $mogclass]));

get '/' => sub {
    header('Content-Type' => 'text/plain');
    return <<EOA
This is a simple REST API abstraction to MogileFS, so that
we can store and retrieve files from mogile, without having to reimplement
a MogileFS client in different languages.

Files are hosted at:
/:namespace/:key

you can HEAD/GET/PUT/DELETE on that endpoint, please README for more details.

EOA

};

get '/:namespace/:key' => sub {
    my $namespace = param('namespace');
    my $key = param('key');
    my $req = request;
    my $can_reproxy = 0;
    my $capabilities = $req->header('X-Proxy-Capabilities');
    if ($capabilities && $capabilities =~ m{\breproxy-file\b}i) {
        $can_reproxy = 1;
    }
    my $mogile_key = join ":", $namespace, $key;
    my @paths = $client->get_paths($mogile_key, { no_verify => 1 });
    return _not_found() unless @paths;
    header('X-Reproxy-URL' => join " ", @paths);
    if ($can_reproxy) {
        status(HTTP_NO_CONTENT);
        return '';
    }
    else {
        status(HTTP_OK);
        header('Content-Type' => 'application/octet-stream');
        ## should we do another request to get x-reproxy-expected-size
        return ''if $req->is_head;
        my $dataref = $client->get_file_data($mogile_key);
        return $$dataref;
    }
};

del '/:namespace/:key' => sub {
    my $namespace = param('namespace');
    my $key = param('key');
    my $mogile_key = join ":", $namespace, $key;
    my $req = request;

    my $rv = $client->delete($mogile_key);
    return _error("Couldn't delete $namespace/$key") unless $rv;
    status(HTTP_NO_CONTENT);
    return '';
};

put '/:namespace/:key' => sub {
    my $namespace = param('namespace');
    my $key = param('key');
    my $mogile_key = join ":", $namespace, $key;

    my $req = request;
    my $dataref = \request->body;

    my $size;
    {
        use bytes;
        $size = bytes::length($$dataref);
    }
    my $opts = { bytes => $size };
    my $rv = $client->store_content($mogile_key, $mogclass, $dataref, $opts);
    status(HTTP_CREATED);
    return '';
};

sub _not_found {
    status(HTTP_NOT_FOUND);
    return "Not such file";
}

sub _error {
    status(HTTP_INTERNAL_SERVER_ERROR);
    return $_[0] || "Server Error"
}

true;
