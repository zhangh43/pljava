/*
 * Copyright (c) 2004-2013 Tada AB and other contributors, as listed below.
 *
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the The BSD 3-Clause License
 * which accompanies this distribution, and is available at
 * http://opensource.org/licenses/BSD-3-Clause
 *
 * Contributors:
 *   Tada AB
 */
package org.postgresql.pljava.example;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.sql.SQLException;

/**
 * Provides a {@link #createTempFile createTempFile} function, expected to fail
 * if it is declared with the <em>trusted</em> {@code java} language.
 */
public class Security {
	/**
	 * The following method should fail if the language in use is trusted.
	 * 
	 * @return The name of a created temporary file.
	 * @throws SQLException
	 */
	public static String createTempFile() throws SQLException {
		try {
			// create new file
			String content = "PL/Java File Creation Test";
			String path = "/tmp/pljava_temp.txt";
			File file = new File(path);

			// if file doesnt exists, then create it
			if (!file.exists()) {
				file.createNewFile();
			}

			FileWriter fw = new FileWriter(file.getAbsoluteFile());
			BufferedWriter bw = new BufferedWriter(fw);
			// write to file
			bw.write(content);
			// close file
			bw.close();
			return "File Created";
		} catch (IOException e) {
			throw new SQLException(e.getMessage());
		}
	}
}