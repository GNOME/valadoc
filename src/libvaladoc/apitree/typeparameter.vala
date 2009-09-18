/*
 * Valadoc - a documentation tool for vala.
 * Copyright (C) 2008 Florian Brosch
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */


using Vala;
using GLib;
using Gee;


public class Valadoc.TypeParameter : Basic, ReturnTypeHandler {
	private Vala.TypeParameter vtypeparam;

	public bool is_vtypeparam ( Vala.TypeParameter vtypeparam ) {
		return this.vtypeparam == vtypeparam;
	}

	public TypeParameter ( Valadoc.Settings settings, Vala.TypeParameter vtypeparam, Basic parent, Tree head ) {
		this.vtypeparam = vtypeparam;
		this.vsymbol = vtypeparam;
		this.settings = settings;
		this.parent = parent;
		this.head = head;
	}

	public TypeReference? type_reference {
		protected set;
		get;
	}

	public void write ( Langlet langlet, void* ptr ) {
		langlet.write_type_parameter ( this, ptr );
	}

	public string? name {
		owned get {
			return this.vtypeparam.name;
		}
	}

	internal void set_type_reference ( ) {
	}
}
