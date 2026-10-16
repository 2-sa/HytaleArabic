using System;
using System.Collections.Generic;
public static class MessageTokens {
    public static string[] Extract(string text) {
        int at=0;
        var names=new SortedSet<string>(StringComparer.Ordinal);
        ReadMessage(text,ref at,false,names);
        var result=new string[names.Count]; names.CopyTo(result); return result;
    }
    private static void White(string s,ref int p) { while(p<s.Length && Char.IsWhiteSpace(s[p])) p++; }
    private static void ReadMessage(string s,ref int p,bool nested,SortedSet<string> names) {
        while(p<s.Length) {
            if(s[p]=='}') { p++; if(nested) return; throw new FormatException("Unexpected closing brace."); }
            if(s[p]!='{') { p++; continue; }
            p++; White(s,ref p); int start=p;
            while(p<s.Length && (Char.IsLetterOrDigit(s[p]) || s[p]=='_')) p++;
            string name=s.Substring(start,p-start); White(s,ref p);
            if(name.Length==0 || p>=s.Length) throw new FormatException("Invalid argument.");
            names.Add(name);
            if(s[p]=='}') { p++; continue; }
            if(s[p]!=',') throw new FormatException("Invalid argument delimiter.");
            p++; White(s,ref p); start=p;
            while(p<s.Length && Char.IsLetter(s[p])) p++;
            string type=s.Substring(start,p-start); White(s,ref p);
            if(type=="plural" || type=="selectordinal" || type=="select") {
                if(p>=s.Length || s[p]!=',') throw new FormatException("Missing selector branches.");
                p++; bool other=false;
                while(true) {
                    White(s,ref p);
                    if(p>=s.Length) throw new FormatException("Unclosed selector.");
                    if(s[p]=='}') { p++; if(!other) throw new FormatException("Missing other branch."); break; }
                    start=p; while(p<s.Length && !Char.IsWhiteSpace(s[p]) && s[p]!='{') p++;
                    string label=s.Substring(start,p-start);
                    if(label.StartsWith("offset:",StringComparison.Ordinal)) continue;
                    if(label=="other") other=true;
                    White(s,ref p);
                    if(p>=s.Length || s[p]!='{') throw new FormatException("Missing branch message.");
                    p++; ReadMessage(s,ref p,true,names);
                    // Hytale's bundled messages also separate branches with commas.
                    White(s,ref p);
                    if(p<s.Length && s[p]==',') p++;
                }
            } else {
                // Simple ICU number/date styles have no nested message branches.
                while(p<s.Length && s[p]!='}') p++;
                if(p>=s.Length) throw new FormatException("Unclosed formatted argument.");
                p++;
            }
        }
        if(nested) throw new FormatException("Unclosed branch message.");
    }
}
