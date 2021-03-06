#!/usr/bin/env ruby
# Package Management System
require "net/http"
require "net/ftp"
require "uri"
require "digest/md5"
require "yaml"

require_relative "manifest.rb"
require_relative "util.rb"
require_relative "sync.rb"
require_relative "actions.rb"

$config_file = "ship.yaml"

$no_confirm = false

$manifests = []

def execute(type, list)
	if type == "" then return true end
	if type != "update" and type != "" and ($manifests.size == 0 || !$manifests.each{|m| break if m.loaded?}.nil?)
		puts "error: no local manifests exist (run update)"
		return
	end
	# God damn I love ruby.
	list.uniq!

	if type != "update" and type != "list"
	if list.size == 0 then return true end
	puts "--- perform action #{type} ---"
	puts "affected packages:"
	puts list.join(" ")
	if !$no_confirm
	print "\nContinue [Y/n]? "
	
	inp = $stdin.gets.chomp
	if inp == "n" or inp == "N" then return true end
	end
	end
	r = false
	case type
	when "sync"
		r=do_sync(list)
	when "update"
		r=do_update(list)
	when "upgrade"
		r=do_upgrade(list)
	when "list"
		r=do_list(list)
	when ""
		return true
	else
		puts "error: type=#{type}, unknown"
	end
	return r
end

get_config=false
ARGV.each{ |arg|
	if get_config
		$config_file = arg
		get_config = false
		next
	end
	if arg == "-c"
		get_config = true
	end
}

# load configuration
yaml = YAML::load_file($config_file)
ROOT = yaml["root"]
LOCAL = yaml["database"]
ARCH  = yaml["arch"]

if ROOT.nil? or LOCAL.nil? or ARCH.nil?
	puts "configuration file error"
	exit 1
end

if ! Dir.exist?(LOCAL)
	Dir.mkdir(LOCAL)
end

if ! Dir.exist?(ROOT)
	`mkdir -p #{ROOT}`
end

puts "loading remote manifests..."
mans = yaml["manifests"]
if mans.nil? or mans.size == 0
	puts "no remote manifests specified: cannot continue"
	exit 1
end
mans.each{ |m|
	print " * " + m["name"] + "..."
	manifest = Manifest.new(LOCAL + "/" + File.basename(m["remote"]), m["remote"], m["name"])
	$manifests << manifest
	if manifest.loaded?
		puts " ok"
	else
		puts " not present (run update)"
	end
}

if ! File.exist?(LOCAL + "/installed.manifest")
	File.new(LOCAL + "/installed.manifest", "w").close
end
print "loading local manifest..."
$installed = Manifest.new(LOCAL + "/installed.manifest", nil, nil)
puts " ok"

list = []
type = ""
if ARGV[0] == "help" or ARGV[0] == "--help"
	puts $PROGRAM_NAME + " - SeaOS package manager"
	puts "usage: #{$PROGRAM_NAME} [options] <action1> <package list 1> <action2> <package list 2> ..."
	puts "options:"
	puts "  --yes   - Don't ask for confirmation"
	puts "actions:"
	puts "  sync    - Install or remove packages"
	puts "  update  - Synchronize manifest files"
	puts "  upgrade - Upgrade packages"
	puts "  list    - List packages (and information)"
	puts
	puts "Actions that take a package list (sync, upgrade, list) read the packages as a list of directions and names: <direction><name>. Directions are single character and non-alphanumeric. Their meaning depends on the action specified for this package list."
	puts " Direction   | Action | Meaning"
	puts "     +       | sync   | Install package"
	puts "     +       | list   | List package's files"
	puts "     +       | upgrade| Upgrade package"
	puts "     -       | sync   | Uninstall package"
	puts "     -       | list   | Only display if package is installed or not"
	puts "The action 'upgrade' does not require directions, they are optional for this action."
	puts
	puts "Groups are also supported. A group is a set of packages that can be collectively referred to by a single name. They are in all caps. Built-in groups are 'ALL' and 'INSTALLED'. ALL refers to all packages available in all repos. INSTALLED refers to all packages listed in the installedmanifest (all installed packages). When referred to with a direction (e.g. +ALL), the direction is applies to all packages in the group."
	puts 
	puts "Examples:"
	puts "Install and remove programs: "
	puts "    #{$PROGRAM_NAME} sync +bash -gcc -binutils +flex"
	puts "        This will install bash and flex, while removing gcc and binutils"
	puts "    #{$PROGRAM_NAME} sync -INSTALLED"
	puts "        Uninstall everything that is currently installed"
	puts "    #{$PROGRAM_NAME} sync +ALL"
	puts "        Install all available packages"
	puts "Sync repositories:"
	puts "    #{$PROGRAM_NAME} update"
	puts "Combining actions:"
	puts "    #{$PROGRAM_NAME} update sync +bash +findutils -diffutils upgrade INSTALLED"
	puts "        Sync repos, install bash and findutils, remove diffutils, upgrade all installed programs."
	
end

ARGV.each { |arg|
	case arg
		when "--yes"
			$no_confirm = true
		when "sync", "update", "upgrade", "list"
			if ! execute(type, list)
				puts "quitting..."
				exit 1
			end
			list = []
			type = arg
		else
			ar = nil
			arg = arg.dup
			if /ALL$/ =~ arg
				ar = []
				$manifests.each{|m|
					m.each_value{|x|
						ar << x[:name]
					}
				}
				arg.slice!("ALL")
			elsif /INSTALLED$/ =~ arg
				ar = []
				$installed.each_value{|x|
					ar << x[:name]
				}
				arg.slice!("INSTALLED")
			end
			tmp_list = []
			if !ar.nil?
				tmp_list += (arg + ar.join(" " + arg)).split(" ")
			else
				tmp_list << arg
			end
			arr = resolve_deps(tmp_list)
			if arr.nil?
				next
			end
			list += arr
	end
}
execute(type, list)

