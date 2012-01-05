/* girdocumentationimporter.vala
 *
 * Copyright (C) 2008-2010  Jürg Billeter
 * Copyright (C) 2011  Luca Bruno
 * Copyright (C) 2011  Florian Brosch
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
 * 	Jürg Billeter <j@bitron.ch>
 * 	Luca Bruno <lucabru@src.gnome.org>
 *  Florian Brosch <flo.brosch@gmail.com>
 */


using Valadoc;
using GLib;



public class Valadoc.Importer.GirDocumentationImporter : DocumentationImporter {
	public override string file_extension { get { return "gir"; } }

	private MarkupTokenType current_token;
	private MarkupSourceLocation begin;
	private MarkupSourceLocation end;
	private MarkupReader reader;

	private DocumentationParser parser;
	private ErrorReporter reporter;
	private Api.SourceFile file;

	private string parent_c_identifier;

	public GirDocumentationImporter (Api.Tree tree, DocumentationParser parser, ModuleLoader modules, Settings settings, ErrorReporter reporter) {
		base (tree, modules, settings);
		this.reporter = reporter;
		this.parser = parser;
	}

	public override void process (string source_file) {
		this.file = new Api.SourceFile (new Api.Package (Path.get_basename (source_file), true, null), source_file, null);
		this.reader = new MarkupReader (source_file, reporter);

		// xml prolog
		next ();
		next ();

		next ();
		parse_repository ();

		reader = null;
		file = null;
	}

	private void attach_comment (string cname, Api.GirSourceComment? comment) {
		if (comment == null) {
			return ;
		}

		Api.Node? node = this.tree.search_symbol_cstr (null, cname);
		if (node == null) {
			return;
		}

		Content.Comment? content = this.parser.parse (node, comment);
		if (content == null) {
			return;
		}

		node.documentation = content;
	}

	private void error (string message) {
		reporter.error (this.file.relative_path, this.begin.line, this.begin.column, this.end.column, this.reader.get_line_content (this.begin.line), message);
	}

	private void next () {
		current_token = reader.read_token (out begin, out end);
	}

	private void start_element (string name) {
		if (current_token != MarkupTokenType.START_ELEMENT || reader.name != name) {
			// error
			error ("expected start element of `%s'".printf (name));
		}
	}

	private void end_element (string name) {
		if (current_token != MarkupTokenType.END_ELEMENT || reader.name != name) {
			// error
			error ("expected end element of `%s'".printf (name));
		}
		next ();
	}

	private const string GIR_VERSION = "1.2";

	private void parse_repository () {
		start_element ("repository");
		if (reader.get_attribute ("version") != GIR_VERSION) {
			error ("unsupported GIR version %s (supported: %s)".printf (reader.get_attribute ("version"), GIR_VERSION));
			return;
		}
		next ();

		while (current_token == MarkupTokenType.START_ELEMENT) {
			if (reader.name == "namespace") {
				parse_namespace ();
			} else if (reader.name == "include") {
				parse_include ();
			} else if (reader.name == "package") {
				parse_package ();
			} else if (reader.name == "c:include") {
				parse_c_include ();
			} else {
				// error
				error ("unknown child element `%s' in `repository'".printf (reader.name));
				skip_element ();
			}
		}
		end_element ("repository");
	}

	private void parse_include () {
		start_element ("include");
		next ();

		end_element ("include");
	}

	private void parse_package () {
		start_element ("package");
		next ();

		end_element ("package");
	}

	private void parse_c_include () {
		start_element ("c:include");
		next ();

		end_element ("c:include");
	}

	private void skip_element () {
		next ();

		int level = 1;
		while (level > 0) {
			if (current_token == MarkupTokenType.START_ELEMENT) {
				level++;
			} else if (current_token == MarkupTokenType.END_ELEMENT) {
				level--;
			} else if (current_token == MarkupTokenType.EOF) {
				error ("unexpected end of file");
				break;
			}
			next ();
		}
	}

	private void parse_namespace () {
		start_element ("namespace");

		next ();
		while (current_token == MarkupTokenType.START_ELEMENT) {
			if (reader.name == "alias") {
				parse_alias ();
			} else if (reader.name == "enumeration") {
				parse_enumeration ();
			} else if (reader.name == "bitfield") {
				parse_bitfield ();
			} else if (reader.name == "function") {
				parse_method ("function");
			} else if (reader.name == "callback") {
				parse_callback ();
			} else if (reader.name == "record") {
				parse_record ();
			} else if (reader.name == "class") {
				parse_class ();
			} else if (reader.name == "interface") {
				parse_interface ();
			} else if (reader.name == "glib:boxed") {
				parse_boxed ("glib:boxed");
			} else if (reader.name == "union") {
				parse_union ();
			} else if (reader.name == "constant") {
				parse_constant ();
			} else {
				// error
				error ("unknown child element `%s' in `namespace'".printf (reader.name));
				skip_element ();
			}
		}

		end_element ("namespace");
	}

	private void parse_alias () {
		start_element ("alias");
		string c_identifier = reader.get_attribute ("c:type");
		next ();

		Api.GirSourceComment? comment = parse_symbol_doc ();
		attach_comment (c_identifier, comment);

		parse_type ();

		end_element ("alias");
	}

	private Api.GirSourceComment? parse_symbol_doc () {
		if (reader.name != "doc") {
			return null;
		}

		start_element ("doc");
		next ();

		Api.GirSourceComment? comment = null;

		if (current_token == MarkupTokenType.TEXT) {
			comment = new Api.GirSourceComment (reader.content, file, begin.line, begin.column, end.line, end.column);
			next ();
		}

		end_element ("doc");
		return comment;
	}

	private Api.SourceComment? parse_doc () {
		if (reader.name != "doc") {
			return null;
		}

		start_element ("doc");
		next ();

		Api.SourceComment? comment = null;

		if (current_token == MarkupTokenType.TEXT) {
			comment = new Api.SourceComment (reader.content, file, begin.line, begin.column, end.line, end.column);
			next ();
		}

		end_element ("doc");
		return comment;
	}

	private void parse_enumeration (string element_name = "enumeration") {
		start_element (element_name);
		this.parent_c_identifier = reader.get_attribute ("c:type");
		next ();

		Api.GirSourceComment? comment = parse_symbol_doc ();
		attach_comment (this.parent_c_identifier, comment);

		while (current_token == MarkupTokenType.START_ELEMENT) {
			if (reader.name == "member") {
				parse_enumeration_member ();
			} else if (reader.name == "function") {
				skip_element ();
			} else {
				// error
				error ("unknown child element `%s' in `%s'".printf (reader.name, element_name));
				skip_element ();
			}
		}

		this.parent_c_identifier = null;
		end_element (element_name);
	}

	private void parse_bitfield () {
		parse_enumeration ("bitfield");
	}

	private void parse_enumeration_member () {
		start_element ("member");
		string c_identifier = reader.get_attribute ("c:identifier");
		next ();

		Api.GirSourceComment? comment = parse_symbol_doc ();
		attach_comment (c_identifier, comment);

		end_element ("member");
	}

	private void parse_return_value (out Api.SourceComment? comment = null) {
		start_element ("return-value");
		next ();

		comment = parse_doc ();

		parse_type ();

		end_element ("return-value");
	}

	private void parse_parameter (out Api.SourceComment? comment, out string param_name) {
		start_element ("parameter");
		param_name = reader.get_attribute ("name");
		next ();

		comment = parse_doc ();

		if (reader.name == "varargs") {
			start_element ("varargs");
			param_name = "...";
			next ();

			end_element ("varargs");
		} else {
			parse_type ();
		}

		end_element ("parameter");
	}

	private void parse_type () {
		skip_element ();
	}

	private void parse_record () {
		start_element ("record");
		this.parent_c_identifier = reader.get_attribute ("c:type");
		if (this.parent_c_identifier.has_suffix ("Private")) {
			this.parent_c_identifier = null;
			skip_element ();
			return ;
		}

		next ();

		Api.GirSourceComment? comment = parse_symbol_doc ();
		attach_comment (this.parent_c_identifier, comment);

		while (current_token == MarkupTokenType.START_ELEMENT) {
			if (reader.name == "field") {
				parse_field ();
			} else if (reader.name == "constructor") {
				parse_constructor ();
			} else if (reader.name == "method") {
				parse_method ("method");
			} else if (reader.name == "function") {
				skip_element ();
			} else if (reader.name == "union") {
				parse_union ();
			} else {
				// error
				error ("unknown child element `%s' in `record'".printf (reader.name));
				skip_element ();
			}
		}

		this.parent_c_identifier = null;
		end_element ("record");
	}

	private void parse_class () {
		start_element ("class");
		this.parent_c_identifier = reader.get_attribute ("c:type");
		next ();

		Api.GirSourceComment? comment = parse_symbol_doc ();
		attach_comment (this.parent_c_identifier, comment);

		while (current_token == MarkupTokenType.START_ELEMENT) {
			if (reader.name == "implements") {
				skip_element ();
			} else if (reader.name == "constant") {
				parse_constant ();
			} else if (reader.name == "field") {
				parse_field ();
			} else if (reader.name == "property") {
				parse_property ();
			} else if (reader.name == "constructor") {
				parse_constructor ();
			} else if (reader.name == "function") {
				parse_method ("function");
			} else if (reader.name == "method") {
				parse_method ("method");
			} else if (reader.name == "virtual-method") {
				parse_method ("virtual-method");
			} else if (reader.name == "union") {
				parse_union ();
			} else if (reader.name == "glib:signal") {
				parse_signal ();
			} else {
				// error
				error ("unknown child element `%s' in `class'".printf (reader.name));
				skip_element ();
			}
		}

		this.parent_c_identifier = null;
		end_element ("class");
	}

	private void parse_interface () {
		start_element ("interface");
		this.parent_c_identifier = reader.get_attribute ("c:type");
		next ();

		Api.GirSourceComment? comment = parse_symbol_doc ();
		attach_comment (this.parent_c_identifier, comment);

		while (current_token == MarkupTokenType.START_ELEMENT) {
			if (reader.name == "prerequisite") {
				skip_element ();
			} else if (reader.name == "field") {
				parse_field ();
			} else if (reader.name == "property") {
				parse_property ();
			} else if (reader.name == "virtual-method") {
				parse_method ("virtual-method");
			} else if (reader.name == "function") {
				parse_method ("function");
			} else if (reader.name == "method") {
				parse_method ("method");
			} else if (reader.name == "glib:signal") {
				parse_signal ();
			} else {
				// error
				error ("unknown child element `%s' in `interface'".printf (reader.name));
				skip_element ();
			}
		}

		this.parent_c_identifier = null;
		end_element ("interface");
	}

	private void parse_field () {
		start_element ("field");
		string c_identifier = reader.get_attribute ("name");
		if (this.parent_c_identifier != null) {
			c_identifier = this.parent_c_identifier + "." + c_identifier;
		}
		next ();

		parse_symbol_doc ();

		parse_type ();

		end_element ("field");
	}

	private void parse_property () {
		start_element ("property");
		string c_identifier = "%s:%s".printf (parent_c_identifier, reader.get_attribute ("name").replace ("-", "_"));
		next ();

		Api.GirSourceComment? comment = parse_symbol_doc ();
		attach_comment (c_identifier, comment);

		parse_type ();

		end_element ("property");
	}

	private void parse_callback () {
		skip_element ();
	}

	private void parse_constructor () {
		parse_function ("constructor");
	}

	private void parse_function (string element_name) {
		start_element (element_name);

		string? c_identifier = null;
		switch (element_name) {
		case "constructor":
		case "function":
		case "method":
			c_identifier = reader.get_attribute ("c:identifier");
			break;

		case "virtual-method":
			c_identifier = "%s->%s".printf (this.parent_c_identifier, reader.get_attribute ("name").replace ("-", "_"));
			break;

		case "glib:signal":
			c_identifier = "%s::%s".printf (this.parent_c_identifier, reader.get_attribute ("name").replace ("-", "_"));
			break;

		default:
			skip_element ();
			return ;
		}

		next ();

		Api.GirSourceComment? comment = parse_symbol_doc ();

		if (current_token == MarkupTokenType.START_ELEMENT && reader.name == "return-value") {
			Api.SourceComment? return_comment;
			parse_return_value (out return_comment);
			if (return_comment != null) {
				if (comment == null) {
					comment = new Api.GirSourceComment ("", file, begin.line, begin.column, end.line, end.column);
				}
				comment.return_comment = return_comment;
			}
		}


		if (current_token == MarkupTokenType.START_ELEMENT && reader.name == "parameters") {
			start_element ("parameters");
			next ();

			while (current_token == MarkupTokenType.START_ELEMENT) {
				Api.SourceComment? param_comment;
				string? param_name;

				parse_parameter (out param_comment, out param_name);

				if (param_comment != null) {
					if (comment == null) {
						comment = new Api.GirSourceComment ("", file, begin.line, begin.column, end.line, end.column);
					}

					comment.add_parameter_content (param_name, param_comment);
				}
			}
			end_element ("parameters");
		}

		attach_comment (c_identifier, comment);
		end_element (element_name);
	}

	private void parse_method (string element_name) {
		parse_function (element_name);
	}

	private void parse_signal () {
		parse_function ("glib:signal");
	}

	private void parse_boxed (string element_name) {
		start_element (element_name);

		this.parent_c_identifier = reader.get_attribute ("name");
		if (this.parent_c_identifier == null) {
			this.parent_c_identifier = reader.get_attribute ("glib:name");
		}

		next ();

		parse_symbol_doc ();

		// TODO: process comments

		while (current_token == MarkupTokenType.START_ELEMENT) {
			if (reader.name == "field") {
				parse_field ();
			} else if (reader.name == "constructor") {
				parse_constructor ();
			} else if (reader.name == "method") {
				parse_method ("method");
			} else if (reader.name == "function") {
				skip_element ();
			} else if (reader.name == "union") {
				parse_union ();
			} else {
				// error
				error ("unknown child element `%s' in `class'".printf (reader.name));
				skip_element ();
			}
		}

		this.parent_c_identifier = null;
		end_element (element_name);
	}

	private void parse_union () {
		start_element ("union");
		this.parent_c_identifier = reader.get_attribute ("c:type");
		next ();

		Api.GirSourceComment? comment = parse_symbol_doc ();
		attach_comment (this.parent_c_identifier, comment);

		while (current_token == MarkupTokenType.START_ELEMENT) {
			if (reader.name == "field") {
				parse_field ();
			} else if (reader.name == "constructor") {
				parse_constructor ();
			} else if (reader.name == "method") {
				parse_method ("method");
			} else if (reader.name == "function") {
				skip_element ();
			} else if (reader.name == "record") {
				parse_record ();
			} else {
				// error
				error ("unknown child element `%s' in `union'".printf (reader.name));
				skip_element ();
			}
		}

		this.parent_c_identifier = null;
		end_element ("union");
	}

	private void parse_constant () {
		start_element ("constant");
		string c_identifier = reader.get_attribute ("c:type");
		next ();

		Api.GirSourceComment? comment = parse_symbol_doc ();
		attach_comment (c_identifier, comment);

		parse_type ();

		end_element ("constant");
	}
}
