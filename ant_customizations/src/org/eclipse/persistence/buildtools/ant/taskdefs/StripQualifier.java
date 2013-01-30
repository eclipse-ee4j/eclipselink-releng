/*******************************************************************************
 * Copyright (c) 2013 Oracle and/or its affiliates. All rights reserved.
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License v1.0 and Eclipse Distribution License v. 1.0
 * which accompanies this distribution.
 * The Eclipse Public License is available at http://www.eclipse.org/legal/epl-v10.html
 * and the Eclipse Distribution License is available at
 * http://www.eclipse.org/org/documents/edl-v10.php.
 *
 * StripQualifier
 *    input    - "version" to reduce to 3-part equivilent
 *    property - Property to store the results in
 *
 * Contributors:
 *     egwin - initial conception and implementation
 */

package org.eclipse.persistence.buildtools.ant.taskdefs;

import org.apache.tools.ant.BuildException;
import org.apache.tools.ant.Project;
import org.apache.tools.ant.Task;
import org.eclipse.persistence.buildtools.helper.Version;
//import org.eclipse.persistence.buildtools.helper.VersionException;

public class StripQualifier extends Task {
    private String input    = null;    // Version String to reduce to 3-part version
    private String property = null;    // Name of Property to set with stripped value
    private Version version = null;    // local: storage for version to strip

    public void execute() throws BuildException {
        if (input == null) {
            throw new BuildException("'input' attribute must be set.", getLocation());
        }
        if (property == null) {
            throw new BuildException("'property' attribute must be set.", getLocation());
        }
        if (property == "") {
            throw new BuildException("'property' cannot be an empty string.", getLocation());
        }
        if ( input.startsWith("${") || input.startsWith("@{") || input == "" ) {
            // If input empty or unexpanded then set value of property to 'NA'
            log("StripQualifier finished.  Input empty or search failed! original value was '" + input + "'.", Project.MSG_VERBOSE);
            throw new BuildException("'input' is empty, or a property value cannot be expanded.", getLocation());
        }
        else {
            // put result into property - overwrites previous value! Not safe for <parallel> tasks
            //try {
                version = new Version(input);
            //} catch ( VersionException e){
            //    log("stripQualifier: Exception detected -> " + e, Project.MSG_VERBOSE);
            //}
           	getProject().setProperty( property, version.get3PartStr() );
            log("StripQualifier finished. Old string of '" + input + "' set to '" + version.get3PartStr() + "' in property '" + property + "'.", Project.MSG_VERBOSE);
        }
    }

    public void setInput(String input) {
        this.input = input;
    }

    public void setProperty(String property) {
        this.property = property;
    }
}
