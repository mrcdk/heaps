package hxd.net;
import cdb.jq.JQuery;
import hxd.net.Property;

private class DrawEvent implements h3d.IDrawable {
	var i : SceneInspector;
	public function new(i) {
		this.i = i;
	}
	public function render( engine : h3d.Engine ) {
		i.sync();
	}
}

class Node {

	public var name(default,set) : String;
	public var icon(default, set) : String;
	public var parent(default, null) : Node;

	public var props : Void -> Array<Property>;

	var childs : Array<Node>;
	var j : cdb.jq.JQuery;
	var jchild : cdb.jq.JQuery;

	public function new( root : JQuery, ?parent) {

		j = root.query("<li>");
		j.html('<i/><div class="content"></div>');

		childs = [];

		this.parent = parent;
		if( parent != null ) {
			if( parent.jchild == null ) {
				parent.jchild = root.query("<ul>");
				parent.jchild.addClass("elt");
				parent.jchild.appendTo(parent.j);
			}
			j.appendTo(parent.jchild);
			parent.childs.push(this);
		} else
			j.appendTo(root);

		j.children("i").click(function(_) {
			if( childs.length > 0 ) {
				j.toggleClass("expand");
				jchild.slideToggle(50);
			}
		});
		j.children(".content").click(function(_) {
			root.find(".selected").removeClass("selected");
			j.addClass("selected");
			onSelect();
		});
	}

	public function getPathName() {
		return name.split(".").join(" ");
	}

	public function getFullPath() {
		var n = getPathName();
		if( parent == null )
			return n;
		return parent.getFullPath() + "." + n;
	}

	public dynamic function onSelect() {
	}

	public function remove() {
		j.dispose();
		for( c in childs )
			c.remove();
		if( parent != null )
			parent.childs.remove(this);
	}

	function set_name(v) {
		j.children(".content").text(v);
		return name = v;
	}

	function set_icon(v) {
		j.children("i").attr("class", "fa fa-"+v);
		return icon = v;
	}

}

private class SceneObject extends Node {

	public var o : h3d.scene.Object;
	public var visible = true;
	public var culled = false;

	public function new(i, o, p) {
		super(i,p);
		this.o = o;
	}

	function objectName( o : h3d.scene.Object ) {
		var name = o.name != null ? o.name : o.toString();
		return name.split(".").join("_");
	}

	override public function getPathName() {
		var name = objectName(o);
		if( o.parent == null )
			return name;
		var idx = Lambda.indexOf(@:privateAccess o.parent.childs, o);
		var count = 0;
		for( i in 0...idx )
			if( objectName(o) == name )
				count++;
		if( count > 0 )
			name += "@" + count;
		return name;
	}

}

class Tool {
	public var name(default,set) : String;
	public var icon(default,set) : String;
	public var click : Void -> Void;
	public var j : JQuery;
	public var jicon : JQuery;
	public var active(get, set) : Bool;
	public function new() {
	}
	function get_active() {
		return j.hasClass("active");
	}
	function set_active(v) {
		j.toggleClass("active", v);
		return v;
	}
	function set_name(v) {
		jicon.attr("alt", v);
		return name = v;
	}
	function set_icon(v) {
		jicon.attr("class", "fa fa-"+v);
		return icon = v;
	}
}

class SceneInspector {

	static var CSS = hxd.res.Embed.getFileContent("hxd/net/inspect.css");

	public var scene(default, set) : h3d.scene.Scene;
	public var connected(get, never): Bool;

	var inspect : PropInspector;
	var jroot : JQuery;
	var event : DrawEvent;
	var oldLog : Dynamic -> haxe.PosInfos -> Void;
	var savedFile : String;
	var sceneObjects : Array<SceneObject> = [];
	var scenePosition = 0;
	var oldLoop : Void -> Void;
	var state : Map<String,{ original : Dynamic, current : Dynamic }>;
	var activeTool : JQuery;
	var rootNodes : Array<Node>;


	public function new( scene, ?host, ?port ) {
		event = new DrawEvent(this);
		savedFile = "sceneProps.js";
		state = new Map();
		//oldLog = haxe.Log.trace;
		//haxe.Log.trace = onTrace;
		inspect = new PropInspector(host, port);
		inspect.resolveProps = resolveProps;
		inspect.onChange = onChange;
		inspect.handleKey = onKey;
		this.scene = scene;
		rootNodes = [];
		sceneObjects = [];

		init();

		addNode("Renderer", "object-group", getRendererProps);
		addTool("Load...", "download", load);
		addTool("Save...", "save", save);
		addTool("Undo", "undo", inspect.undo);
		addTool("Repeat", "repeat", inspect.redo);
		var pause : Tool = null;
		pause = addTool("Pause", "pause", function() {
			if( oldLoop != null ) {
				hxd.System.setLoop(oldLoop);
				oldLoop = null;
			} else {
				oldLoop = hxd.System.getCurrentLoop();
				hxd.System.setLoop(pauseLoop);
			}
			pause.active = oldLoop != null;
		});
	}

	inline function get_connected() {
		return inspect.connected;
	}

	public inline function J( ?elt : cdb.jq.Dom, ?query : String ) {
		return inspect.J(elt,query);
	}

	public function getActiveTool() {
		return activeTool;
	}

	public function createPanel( title ) {
		return inspect.createPanel(title);
	}

	public function addTool( name : String, icon : String, click : Void -> Void ) {
		var t = new Tool();
		t.j = J("<li>");
		t.jicon = J("<i>").appendTo(t.j);
		t.j.click(function(_) t.click());
		t.name = name;
		t.icon = icon;
		t.click = click;
		t.j.appendTo(jroot.find("#toolbar"));
		return t;
	}

	function onKey( e : cdb.jq.Event ) {
		switch( e.keyCode ) {
		case 'S'.code if( e.ctrlKey ):
			save();
		case hxd.Key.F1:
			load();
		default:
		}
	}

	function onTrace( v : Dynamic, ?pos : haxe.PosInfos ) {
		if( !inspect.connected )
			oldLog(v, pos);
		else {
			var vstr = null;
			if( pos.customParams != null ) {
				pos.customParams.unshift(v);
				vstr = [for( v in pos.customParams ) Std.string(v)].join(",");
			} else
				vstr = Std.string(v);
			J("<pre>").addClass("line").text(pos.fileName+"(" + pos.lineNumber + ") : " + vstr).appendTo(J("#log"));
		}
	}

	function set_scene(s:h3d.scene.Scene) {
		if( scene != null )
			scene.removePass(event);
		if( s != null )
			s.addPass(event, true);
		return scene = s;
	}

	function pauseLoop() {
		scene.setElapsedTime(0);
		h3d.Engine.getCurrent().render(scene);
	}

	function init() {
		jroot = J(inspect.getRoot());
		jroot.html('
			<style>$CSS</style>
			<ul id="toolbar" class="toolbar">
			</ul>
			<div id="scene" class="panel" caption="Scene">
				<ul id="scontent" class="elt">
				</ul>
			</div>
			<div id="props" class="panel" caption="Properties">
			</div>
			<div id="log" class="panel" caption="Log">
			</div>
		');
		jroot.attr("title", "Inspect");
		var scene = J("#scene");
		scene.dock(jroot.get(), Left, 0.2);
		J("#log").dock(jroot.get(), Down, 0.3);
		J("#props").dock(scene.get(), Down, 0.5);
	}

	function load() {
		hxd.File.browse(function(b) {
			savedFile = b.fileName;
			b.load(function(bytes) {
				var o : Dynamic = haxe.Json.parse(bytes.toString());
				function browseRec( path : Array<String>, v : Dynamic ) {
					switch( Type.typeof(v) ) {
					case TNull, TInt, TFloat, TBool, TClass(_):
						var path = path.join(".");
						state.set(path, { original : null, current : v });
					case TUnknown, TFunction, TEnum(_):
						throw "Invalid value " + v;
					case TObject:
						for( f in Reflect.fields(v) ) {
							var fv = Reflect.field(v, f);
							path.push(f);
							browseRec(path, fv);
							path.pop();
						}
					}
				}
				browseRec([], o);
				for( s in state.keys() )
					inspect.setPathPropValue(s, state.get(s).current);
			});

		},{ defaultPath : savedFile, fileTypes : [ { name:"Scene Props", extensions:["js"] } ] } );
	}

	function save() {
		var o : Dynamic = { };
		for( s in state.keys() ) {
			var path = s.split(".");
			var o = o;
			while( path.length > 1 ) {
				var name = path.shift();
				var s = Reflect.field(o, name);
				if( s == null ) {
					s = { };
					Reflect.setField(o, name, s);
				}
				o = s;
			}
			Reflect.setField(o, path[0], state.get(s).current);
		}
		var js = haxe.Json.stringify(o, null, "\t");
		hxd.File.saveAs(haxe.io.Bytes.ofString(js), { defaultPath : savedFile, saveFileName : function(name) savedFile = name } );
	}

	public function addNode( name : String, icon : String, ?getProps : Void -> Array<Property>, ?parent : Node ) : Node {
		var n = new Node(J("#scontent"), parent);
		n.name = name;
		n.icon = icon;
		n.props = getProps;
		if( getProps != null )
			n.onSelect = function() fillProps(n.getFullPath(), getProps());
		if( parent == null )
			rootNodes.push(n);
		return n;
	}

	public function sync() {
		if( scene == null || !inspect.connected ) return;
		scenePosition = 0;
		syncRec(scene, null);
		while( sceneObjects.length > scenePosition )
			sceneObjects.pop().remove();
	}

	function resolveProps( path : Array<String> ) {
		var cur = null;
		var nodes = rootNodes;
		while( true ) {
			var k = path.shift();
			if( k == null ) break;
			var found = false;
			for( n in nodes ) {
				if( n.getPathName() == k ) {
					found = true;
					cur = n;
					nodes = @:privateAccess n.childs;
					break;
				}
			}
			if( !found ) {
				path.unshift(k);
				break;
			}
		}
		return cur == null || cur.props == null ? null : cur.props();
	}

	function getObjectIcon( o : h3d.scene.Object) {
		if( Std.is(o, h3d.scene.Skin) )
			return "child";
		if( Std.is(o, h3d.scene.Mesh) )
			return "cube";
		if( Std.is(o, h3d.scene.CustomObject) )
			return "globe";
		if( Std.is(o, h3d.scene.Scene) )
			return "picture-o";
		if( Std.is(o, h3d.scene.Light) )
			return "lightbulb-o";
		return null;
	}

	@:access(hxd.net.Node)
	function syncRec( o : h3d.scene.Object, p : SceneObject ) {
		var so = sceneObjects[scenePosition];
		if( so == null || so.o != o || so.parent != p ) {
			so = new SceneObject(J("#scontent"), o, p);
			so.name = o.name != null ? o.name : o.toString();
			sceneObjects.insert(scenePosition, so);
			var icon = getObjectIcon(o);
			so.icon = icon == null ? "circle-o" : getObjectIcon(o);
			so.props = function() return getObjectProps(o);
			so.onSelect = function() fillProps(so.getFullPath(), getObjectProps(o));
			if( p == null )
				rootNodes.push(so);
		}
		if( o.visible != so.visible ) {
			so.visible = o.visible;
			so.j.toggleClass("hidden");
		}
		@:privateAccess if( o.culled != so.culled ) {
			so.culled = o.culled;
			so.j.toggleClass("culled");
		}

		scenePosition++;
		if( o.numChildren > 0 ) {
			for( c in o )
				syncRec(c, so);
		} else if( so.jchild != null ) {
			so.jchild.remove();
			so.jchild = null;
			for( o in so.childs )
				o.remove();
		}
	}

	function onChange( path : String, oldV : Dynamic, newV : Dynamic ) {
		var s = state.get(path);
		if( s == null )
			state.set(path, { original : oldV, current : newV } );
		else {
			if( inspect.sameValue(s.original,newV) )
				state.remove(path);
			else
				s.current = newV;
		}
	}

	function getShaderProps( s : hxsl.Shader ) {
		var props = [];
		var data = @:privateAccess s.shader;
		var vars = data.data.vars.copy();
		vars.sort(function(v1, v2) return Reflect.compare(v1.name, v2.name));
		for( v in vars ) {
			switch( v.kind ) {
			case Param:
				var name = v.name+"__";
				function set(val:Dynamic) {
					Reflect.setField(s, name, val);
					if( hxsl.Ast.Tools.isConst(v) )
						@:privateAccess s.constModified = true;
				}
				switch( v.type ) {
				case TBool:
					props.push(PBool(v.name, function() return Reflect.field(s,name), set ));
				case TInt:
					props.push(PInt(v.name, function() return Reflect.field(s,name), set ));
				case TFloat:
					props.push(PFloat(v.name, function() return Reflect.field(s, name), set));
				case TVec(size = (3 | 4), VFloat) if( v.name.toLowerCase().indexOf("color") >= 0 ):
					props.push(PColor(v.name, size == 4, function() return Reflect.field(s, name), set));
				case TSampler2D, TSamplerCube:
					props.push(PTexture(v.name, function() return Reflect.field(s, name), set));
				case TVec(size, VFloat):
					props.push(PFloats(v.name, function() {
						var v : h3d.Vector = Reflect.field(s, name);
						var vl = [v.x, v.y];
						if( size > 2 ) vl.push(v.z);
						if( size > 3 ) vl.push(v.w);
						return vl;
					}, function(vl) {
						set(new h3d.Vector(vl[0], vl[1], vl[2], vl[3]));
					}));
				case TArray(_):
					props.push(PString(v.name, function() {
						var a : Array<Dynamic> = Reflect.field(s, name);
						return a == null ? "NULL" : "(" + a.length + " elements)";
					}, function(val) {}));
				default:
					props.push(PString(v.name, function() return ""+Reflect.field(s,name), function(val) { } ));
				}
			default:
			}
		}

		var name = data.data.name;
		if( StringTools.startsWith(name, "h3d.shader.") )
			name = name.substr(11);
		name = name.split(".").join(" "); // no dot in prop name !

		return PGroup("shader "+name, props);
	}

	function colorize( code : String ) {
		code = code.split("\t").join("    ");
		code = StringTools.htmlEscape(code);
		code = ~/\b((var)|(function)|(if)|(else)|(for)|(while))\b/g.replace(code, "<span class='kwd'>$1</span>");
		code = ~/(@[A-Za-z]+)/g.replace(code, "<span class='meta'>$1</span>");
		return code;
	}

	function getMaterialProps( mat : h3d.mat.Material ) {
		var props = [];
		props.push(PString("name", function() return mat.name == null ? "" : mat.name, function(n) mat.name = n == "" ? null : n));
		for( pass in mat.getPasses() ) {
			var pl = [
				PBool("Lights", function() return pass.enableLights, function(v) pass.enableLights = v),
				PEnum("Cull", h3d.mat.Data.Face, function() return pass.culling, function(v) pass.culling = v),
				PEnum("BlendSrc", h3d.mat.Data.Blend, function() return pass.blendSrc, function(v) pass.blendSrc = pass.blendAlphaSrc = v),
				PEnum("BlendDst", h3d.mat.Data.Blend, function() return pass.blendDst, function(v) pass.blendDst = pass.blendAlphaDst = v),
				PBool("DepthWrite", function() return pass.depthWrite, function(b) pass.depthWrite = b),
				PEnum("DepthTest", h3d.mat.Data.Compare, function() return pass.depthTest, function(v) pass.depthTest = v)
			];

			var shaders = [for( s in pass.getShaders() ) s];
			shaders.reverse();
			for( index in 0...shaders.length ) {
				var s = shaders[index];
				var p = getShaderProps(s);
				p = PPopup(p, ["Toggle", "View Source"], function(j, i) {
					switch( i ) {
					case 0:
						if( index == 0 ) return; // Don't allow toggle base shader
						if( !pass.removeShader(s) )
							pass.addShaderAt(s, shaders.length - (index + 1));
						j.toggleClass("disable");
					case 1:
						var shader = @:privateAccess s.shader;
						var p = inspect.createPanel(shader.data.name+" shader");
						var toString = hxsl.Printer.shaderToString;
						var code = toString(shader.data);
						p.html("<pre class='code'>"+colorize(code)+"</pre>");
					}

				});
				pl.push(p);
			}

			var p = PGroup("pass " + pass.name, pl);
			p = PPopup(p, ["Toggle", "View Shader"], function(j, i) {
				switch( i ) {
				case 0:
					if( !mat.removePass(pass) )
						mat.addPass(pass);
					j.toggleClass("disable");
				case 1:
					var p = inspect.createPanel(pass.name+" shader");

					var shader = scene.renderer.compileShader(pass);
					var toString = hxsl.Printer.shaderToString;
					var code = toString(shader.vertex.data) + "\n\n" + toString(shader.fragment.data);
					p.html("<pre class='code'>"+colorize(code)+"</pre>");
				}
			});
			props.push(p);
		}
		return PGroup("Material",props);
	}

	function getLightProps( l : h3d.scene.Light ) {
		var props = [];
		props.push(PColor("color", false, function() return l.color, function(c) l.color.load(c)));
		props.push(PInt("priority", function() return l.priority, function(p) l.priority = p));
		props.push(PBool("enableSpecular", function() return l.enableSpecular, function(b) l.enableSpecular = b));
		var dl = Std.instance(l, h3d.scene.DirLight);
		if( dl != null )
			props.push(PFloats("direction", function() return [dl.direction.x, dl.direction.y, dl.direction.z], function(fl) dl.direction.set(fl[0], fl[1], fl[2])));
		var pl = Std.instance(l, h3d.scene.PointLight);
		if( pl != null )
			props.push(PFloats("params", function() return [pl.params.x, pl.params.y, pl.params.z], function(fl) pl.params.set(fl[0], fl[1], fl[2], fl[3])));
		return PGroup("Light", props);
	}

	function getObjectProps( o : h3d.scene.Object ) {
		var props = [];
		props.push(PString("name", function() return o.name == null ? "" : o.name, function(v) o.name = v == "" ? null : v));
		props.push(PFloat("x", function() return o.x, function(v) o.x = v));
		props.push(PFloat("y", function() return o.y, function(v) o.y = v));
		props.push(PFloat("z", function() return o.z, function(v) o.z = v));
		props.push(PBool("visible", function() return o.visible, function(v) o.visible = v));

		if( o.isMesh() ) {
			var multi = Std.instance(o, h3d.scene.MultiMaterial);
			if( multi != null && multi.materials.length > 1 ) {
				for( m in multi.materials )
					props.push(getMaterialProps(m));
			} else
				props.push(getMaterialProps(o.toMesh().material));
		} else {
			var c = Std.instance(o, h3d.scene.CustomObject);
			if( c != null )
				props.push(getMaterialProps(c.material));
			var l = Std.instance(o, h3d.scene.Light);
			if( l != null )
				props.push(getLightProps(l));
		}
		return props;
	}

	function fillProps( basePath : String, props : Array<Property> ) {
		var j = J("#props");
		j.text("");
		var t = inspect.makeProps(basePath, props);
		t.appendTo(j);
	}

	function getTextures( t : h3d.impl.TextureCache ) {
		var cache = @:privateAccess t.cache;
		var props = [];
		for( i in 0...cache.length ) {
			var t = cache[i];
			props.push(PTexture(t.name, function() return t, null));
		}
		return props;
	}

	function getDynamicProps( v : Dynamic ) {
		var fx = Std.instance(v,h3d.pass.ScreenFx);
		if( fx != null )
			return [getShaderProps(fx.shader)];
		var s = Std.instance(v, hxsl.Shader);
		if( s != null )
			return [getShaderProps(s)];
		return null;
	}

	function getPassProps( p : h3d.pass.Base ) {
		var props = [];
		var def = Std.instance(p, h3d.pass.Default);
		if( def == null ) return props;

		var fields = Type.getInstanceFields(Type.getClass(p));
		fields.sort(Reflect.compare);
		for( f in fields ) {
			var pl = getDynamicProps(Reflect.field(p, f));
			if( pl != null )
				props.push(PGroup(f,pl));
		}

		for( t in getTextures(@:privateAccess def.tcache) )
			props.push(t);

		return props;
	}

	function getRendererProps() {
		var props = [];
		var ls = scene.lightSystem;
		props.push(PGroup("LightSystem", [
			PInt("maxLightsPerObject", function() return ls.maxLightsPerObject, function(s) ls.maxLightsPerObject = s),
			PColor("ambientLight", false, function() return ls.ambientLight, function(v) ls.ambientLight = v),
			PBool("perPixelLighting", function() return ls.perPixelLighting, function(b) ls.perPixelLighting = b),
		]));

		var r = scene.renderer;

		var tex = getTextures(@:privateAccess r.tcache);
		if( tex.length > 0 )
			props.push( PGroup("Textures", tex) );

		var pmap = new Map();
		for( p in @:privateAccess r.allPasses ) {
			if( pmap.exists(p.p) ) continue;
			pmap.set(p.p, true);
			props.push(PGroup("Pass " + p.name, getPassProps(p.p)));
		}

		var fields = Type.getInstanceFields(Type.getClass(r));
		fields.sort(Reflect.compare);
		for( f in fields ) {
			var pl = getDynamicProps(Reflect.field(r, f));
			if( pl != null )
				props.push(PGroup(f,pl));
		}
		return props;
	}

}