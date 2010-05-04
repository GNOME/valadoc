/* doclet.vala
 *
 * Copyright (C) 2010 Luca Bruno
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Luca Bruno <lethalman88@gmail.com>
 */

using Valadoc;
using Valadoc.Api;
using Valadoc.Content;

namespace Gtkdoc.Config {
	public static bool nohtml;
	public static string library_filename;
	public static string ignore_headers;
	public static string deprecated_guards;
	public static string ignore_decorators;

	private static const GLib.OptionEntry[] options = {
			{ "library", 'l', 0, OptionArg.FILENAME, ref library_filename, "Shared library path", "FILENAME" },
			{ "ignore-headers", 'x', 0, OptionArg.STRING, ref ignore_headers, "A space-separated list of header files not to scan", "FILES" },
			{ "deprecated-guards", 'd', 0, OptionArg.STRING, ref deprecated_guards, "A |-separated list of symbols used as deprecation guards", "GUARDS" },
			{ "ignore-decorators", 0, 0, OptionArg.STRING, ref ignore_decorators, "A |-separated list of addition decorators in declarations that should be ignored", "DECS" },
			{ "nohtml", 0, 0, OptionArg.NONE, ref nohtml, "Disable HTML generation", null },
			{ null }
		};

	public static bool parse (string[] rargs) {
		string[] args = { "gtkdoc" };
		foreach (var arg in rargs) {
			args += arg;
		}

		try {
			var opt_context = new OptionContext ("- Vala GTK-Doc");
			opt_context.set_help_enabled (true);
			opt_context.add_main_entries (options, null);
			opt_context.parse (ref args);
		} catch (OptionError e) {
			warning ("GtkDoc: Error: %s", e.message);
			warning ("GtkDoc: Run '-X --help' to see a full list of available command line options.\n");
			return false;
		}

		return true;
	}
}



public class Gtkdoc.Director : Valadoc.Doclet, Object {
	private Settings settings;
	private Api.Tree tree;
	private string[] vala_headers;
	private string[] c_headers;

	/*
	1) Scan normal code, this generates -decl.txt for both C and Vala.
	2) Scan C code into a temp cscan directory. This generates C sections.
	Move C -sections.txt file to the real output -sections.txt.
	3) Generate and append Vala sections to -sections.txt.
	Done. Now we have -decl.txt of the whole code and -sections.txt containing C sections
	and Vala sections.
	*/
	public void process (Settings settings, Api.Tree tree) {
		this.settings = settings;
		if (!Config.parse (settings.pluginargs)) {
			return;
		}
		this.tree = tree;

		DirUtils.create_with_parents (settings.path, 0777);

		find_headers ();
		if (vala_headers.length <= 0) {
			warning ("GtkDoc: No vala header found");
			return;
		}
	   
		if (!scan (settings.path)) {
			return;
		}

		var cscan_dir = Path.build_filename (settings.path, "cscan");
		DirUtils.create_with_parents (cscan_dir, 0777);

		if (!scan (cscan_dir, vala_headers)) {
			return;
		}

		FileUtils.rename (Path.build_filename (cscan_dir, "%s-sections.txt".printf (settings.pkg_name)),
						Path.build_filename (settings.path, "%s-sections.txt".printf (settings.pkg_name)));

		var generator = new Gtkdoc.Generator ();
		if (!generator.execute (settings, tree))
		return;

		if (!scangobj ()) {
			return;
		}

		if (!mkdb ()) {
			return;
		}

		if (!mkhtml ()) {
			return;
		}
	}

	private void find_headers () {
		vala_headers = new string[]{};
		c_headers = new string[]{};
		Dir dir;
		try {
			dir = Dir.open (settings.basedir ?? ".");
		} catch (Error e) {
			warning ("GtkDoc: Can't open %s: %s", settings.basedir, e.message);
			return;
		}

		string filename;

		while ((filename = dir.read_name()) != null) {
			if (filename.has_suffix (".h")) {
				var stream = FileStream.open (filename, "r");
				if (stream != null) {
					var line = stream.read_line ();
					if (line != null) {
						if (line.str ("generated by valac") != null) {
							vala_headers += filename;
						} else {
							c_headers += filename;
						}
					}
				}
			} else if (filename.has_suffix (".c")) {
				try {
					string contents;
					FileUtils.get_contents (filename, out contents);
					FileUtils.set_contents (Path.build_filename (settings.path, "ccomments", Path.get_basename (filename)), contents);
				} catch (Error e) {
					warning ("GtkDoc: Can't copy %s", filename);
					return;
				}
			}
		}
	}

	private bool scan (string output_dir, string[]? ignore_headers = null) {
		string[] args = { "gtkdoc-scan",
						"--module", settings.pkg_name,
						"--source-dir", realpath (settings.basedir ?? "."),
						"--output-dir", output_dir,
						"--rebuild-sections", "--rebuild-types" };
		string ignored = "";

		if (ignore_headers != null) {
			ignored = string.joinv (" ", ignore_headers);
		}

		if (Config.ignore_headers != null) {
			ignored = "%s %s".printf (ignored, Config.ignore_headers);
		}

		if (ignored != "") {
			args += "--ignore-headers";
			args += ignored;
		}

		if (Config.deprecated_guards != null) {
			args += "--deprecated-guards";
			args += Config.deprecated_guards;
		}

		if (Config.ignore_decorators != null) {
			args += "--ignore-decorators";
			args += Config.ignore_decorators;
		}

		try {
			Process.spawn_sync (settings.path, args, null, SpawnFlags.SEARCH_PATH, null, null, null);
		} catch (Error e) {
			warning ("gtkdoc-scan: %s", e.message);
			return false;
		}

		return true;
	}

	private bool scangobj () {
		if (Config.library_filename == null) {
			return true;
		}

		var library = realpath (Config.library_filename);

		string[] pc = { "pkg-config" };
		foreach (var package in tree.get_package_list()) {
			if (package.is_package)
			pc += package.name;
		}

		var pc_cflags = pc;
		pc_cflags += "--cflags";
		var pc_libs = pc;
		pc_libs += "--libs";
	
		try {
			string stderr;
			int status;

			string cflags;
			Process.spawn_sync (null, pc_cflags, null, SpawnFlags.SEARCH_PATH, null, out cflags, out stderr, out status);
			if (status != 0) {
				warning ("GtkDoc: pkg-config cflags error: %s\n", stderr);
				return false;
			}
			cflags = cflags.strip ();

			string libs;
			Process.spawn_sync (null, pc_libs, null, SpawnFlags.SEARCH_PATH, null, out libs, out stderr, out status);
			if (status != 0) {
				warning ("GtkDoc: pkg-config libs error: %s\n", stderr);
				return false;
			}

			libs = libs.strip ();

			string[] args = { "gtkdoc-scangobj",
							  "--module", settings.pkg_name,
							  "--types", "%s.types".printf (settings.pkg_name),
							  "--output-dir", settings.path };

			string[] env = { "CFLAGS=%s".printf (cflags),
							 "LDFLAGS=%s %s".printf (libs, library) };

			foreach (var evar in Environment.list_variables()) {
				env += "%s=%s".printf (evar, Environment.get_variable(evar));
			}

			Process.spawn_sync (settings.path, args, env, SpawnFlags.SEARCH_PATH, null, null, null);
		} catch (Error e) {
			warning ("gtkdoc-scangobj: %s", e.message);
			return false;
		}

		return true;
	}

	private bool mkdb () {
		var code_dir = Path.build_filename (settings.path, "ccomments");

		try {
			Process.spawn_sync (settings.path,
								{ "gtkdoc-mkdb",
									"--module", settings.pkg_name,
									"--source-dir", code_dir,
									"--output-format", "xml",
									"--sgml-mode",
									"--main-sgml-file", "%s-docs.xml".printf (settings.pkg_name),
									"--name-space", settings.pkg_name },
								null, SpawnFlags.SEARCH_PATH, null, null, null);
		} catch (Error e) {
			warning ("gtkdoc-mkdb: %s", e.message);
			return false;
		}

		return true;
	}

	private bool mkhtml () {
		if (Config.nohtml) {
			return true;
		}

		var html_dir = Path.build_filename (settings.path, "html");
		DirUtils.create_with_parents (html_dir, 0777);

		try {
			Process.spawn_sync (html_dir,
								{"gtkdoc-mkhtml",
									settings.pkg_name, "../%s-docs.xml".printf (settings.pkg_name)},
								null, SpawnFlags.SEARCH_PATH, null, null, null);
		} catch (Error e) {
			warning ("gtkdoc-mkhtml: %s", e.message);
			return false;
		}

		/* fix xrefs for regenerated html */
		try {
			Process.spawn_sync (settings.path,
								{ "gtkdoc-fixxref",
									"--module", settings.pkg_name,
									"--module-dir", html_dir,
									"--html-dir", html_dir },
								null, SpawnFlags.SEARCH_PATH, null, null, null);
		} catch (Error e) {
			warning ("gtkdoc-fixxref: %s", e.message);
			return false;
		}

		return true;
	}
}

[ModuleInit]
public Type register_plugin ( ) {
	return typeof ( Gtkdoc.Director );
}

