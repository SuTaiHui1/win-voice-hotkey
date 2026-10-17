using System;
using System.Collections.Generic;
using System.Web.Script.Serialization;
internal static class PanelCoreUnitCheck {
    static int passed;
    static void Check(string expected, VoicePanelCore.Candidate[] candidates, Func<bool> active, string action) {
        string json=VoicePanelCore.Execute(candidates,active,17,action);
        var result=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(json);
        if((string)result["Status"]!=expected || (bool)result["CloseInvoked"] || (bool)result["UsesGlobalKeys"] || (bool)result["UsesMicrophone"])
            throw new Exception("Unexpected bounded result: "+json);
        passed++;
    }
    static int Main() {
        try {
            var empty=new VoicePanelCore.Candidate[0];
            Check("no_verified_panel",empty,()=>true,"close");
            Check("panel_absent",empty,()=>true,"toggle");
            Check("panel_absent",empty,()=>true,"presence");
            Check("rejected",empty,()=>false,"toggle");
            Check("rejected",empty,()=>true,"unknown");
            Check("rejected",null,()=>true,"toggle");
            Check("rejected",new VoicePanelCore.Candidate[17],()=>true,"toggle");
            Check("rejected",new VoicePanelCore.Candidate[]{null},()=>true,"toggle");
            Console.WriteLine("{\"passed\":"+passed+",\"real_UIA_invoked\":false,\"microphone_used\":false}");
            return 0;
        } catch(Exception e) {Console.Error.WriteLine(e);return 1;}
    }
}
