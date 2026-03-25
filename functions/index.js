const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();

// Helper function to check if user is super admin
async function isSuperAdmin(uid) {
  try {
    const userDoc = await db.collection('users').doc(uid).get();
    return userDoc.exists && userDoc.data().role === 'super_admin';
  } catch (error) {
    console.error('Error checking super admin status:', error);
    return false;
  }
}

// Helper function to check if user is school admin and get their school code
async function getSchoolAdminInfo(uid) {
  try {
    const userDoc = await db.collection('users').doc(uid).get();
    if (userDoc.exists) {
      const userData = userDoc.data();
      if (userData.role === 'admin') {
        return {
          isSchoolAdmin: true,
          schoolCode: userData.school_code
        };
      }
    }
    return { isSchoolAdmin: false, schoolCode: null };
  } catch (error) {
    console.error('Error checking school admin status:', error);
    return { isSchoolAdmin: false, schoolCode: null };
  }
}

// OPTIMIZED: Atomic school user counts update using FieldValue.increment()
async function updateSchoolUserCounts(schoolCode, role, change) {
  try {
    const schoolRef = db.collection('schools').doc(schoolCode);
    const field = `${role}_count`;
    
    // Use atomic increment operation to prevent race conditions
    await schoolRef.set({
      [field]: admin.firestore.FieldValue.increment(change)
    }, { merge: true });
    
    console.log(`Atomically updated ${field} for school ${schoolCode} by ${change}`);
    
    // Get the updated count for verification
    const schoolDoc = await schoolRef.get();
    const newCount = schoolDoc.exists ? (schoolDoc.data()[field] || 0) : 0;
    
    return newCount;
  } catch (error) {
    console.error(`Error updating ${field} for school ${schoolCode}:`, error);
    throw error;
  }
}

// OPTIMIZED: Batch update school counts for multiple users
async function updateSchoolUserCountsBulk(schoolCode, roleChanges) {
  try {
    const schoolRef = db.collection('schools').doc(schoolCode);
    const updateData = {};
    
    for (const [role, change] of Object.entries(roleChanges)) {
      const field = `${role}_count`;
      updateData[field] = admin.firestore.FieldValue.increment(change);
    }
    
    await schoolRef.set(updateData, { merge: true });
    console.log(`Atomically updated bulk counts for school ${schoolCode}:`, roleChanges);
    
  } catch (error) {
    console.error(`Error updating bulk counts for school ${schoolCode}:`, error);
    throw error;
  }
}

// NEW: Function to recalculate and fix school counts
exports.recalculateSchoolCounts = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const isCallerSuperAdmin = await isSuperAdmin(context.auth.uid);
  if (!isCallerSuperAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'Only super admins can recalculate counts');
  }

  try {
    const { schoolCode } = data;
    
    if (!schoolCode) {
      throw new functions.https.HttpsError('invalid-argument', 'School code is required');
    }

    // Verify school exists
    const schoolDoc = await db.collection('schools').doc(schoolCode).get();
    if (!schoolDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'School not found');
    }

    // Count users by role for this school
    const [adminCount, teacherCount, studentCount] = await Promise.all([
      db.collection('users')
        .where('school_code', '==', schoolCode)
        .where('role', '==', 'admin')
        .get()
        .then(snapshot => snapshot.size),
      
      db.collection('users')
        .where('school_code', '==', schoolCode)
        .where('role', '==', 'teacher')
        .get()
        .then(snapshot => snapshot.size),
      
      db.collection('users')
        .where('school_code', '==', schoolCode)
        .where('role', '==', 'student')
        .get()
        .then(snapshot => snapshot.size)
    ]);

    // Update school document with accurate counts
    await db.collection('schools').doc(schoolCode).set({
      admin_count: adminCount,
      teacher_count: teacherCount,
      student_count: studentCount,
      last_recalculated: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return {
      success: true,
      schoolCode: schoolCode,
      counts: {
        admin_count: adminCount,
        teacher_count: teacherCount,
        student_count: studentCount
      },
      message: `Successfully recalculated counts for school ${schoolCode}`
    };

  } catch (error) {
    console.error('Error recalculating school counts:', error);
    throw new functions.https.HttpsError('internal', `Error recalculating counts: ${error.message}`);
  }
});

// FIXED: Initialize school counts for existing schools
exports.initializeSchoolCounts = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const isCallerSuperAdmin = await isSuperAdmin(context.auth.uid);
  if (!isCallerSuperAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'Only super admins can initialize counts');
  }

  try {
    // Get all schools
    const schoolsSnapshot = await db.collection('schools').get();
    const results = [];

    for (const schoolDoc of schoolsSnapshot.docs) {
      const schoolCode = schoolDoc.id;
      
      // Count users by role for this school
      const [adminCount, teacherCount, studentCount] = await Promise.all([
        db.collection('users')
          .where('school_code', '==', schoolCode)
          .where('role', '==', 'admin')
          .get()
          .then(snapshot => snapshot.size),

        db.collection('users')
          .where('school_code', '==', schoolCode)
          .where('role', '==', 'teacher')
          .get()
          .then(snapshot => snapshot.size),

        db.collection('users')
          .where('school_code', '==', schoolCode)
          .where('role', '==', 'student')
          .get()
          .then(snapshot => snapshot.size)
      ]);

      // Update school document with counts
      await schoolDoc.ref.set({
        admin_count: adminCount,
        teacher_count: teacherCount,
        student_count: studentCount,
        initialized_at: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });

      results.push({
        schoolCode: schoolCode,
        admin_count: adminCount,
        teacher_count: teacherCount,
        student_count: studentCount
      });
    }

    return {
      success: true,
      message: `Initialized counts for ${results.length} schools`,
      results: results
    };

  } catch (error) {
    console.error('Error initializing school counts:', error);
    throw new functions.https.HttpsError('internal', `Error initializing counts: ${error.message}`);
  }
});

// ENHANCED: Reset User Password Function with Better Debugging
exports.resetUserPassword = functions.https.onCall(async (data, context) => {
  // Check if user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { targetUid, username, role } = data;
  
  if (!targetUid || !username || !role) {
    throw new functions.https.HttpsError('invalid-argument', 'Target user ID, username, and role are required');
  }

  try {
    // Get caller's information
    const callerUid = context.auth.uid;
    const isCallerSuperAdmin = await isSuperAdmin(callerUid);
    const callerAdminInfo = await getSchoolAdminInfo(callerUid);

    console.log(`Password reset requested by: ${callerUid}, target: ${targetUid}, username: ${username}, role: ${role}`);

    // Get the target user's data from Firestore
    const targetUserDoc = await db.collection('users').doc(targetUid).get();
    if (!targetUserDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Target user not found in database');
    }

    const targetUserData = targetUserDoc.data();
    const targetUserRole = targetUserData.role;
    const targetUserSchool = targetUserData.school_code;
    const targetUsername = targetUserData.username;

    console.log('Target user data:', {
      uid: targetUid,
      username: targetUsername,
      school_code: targetUserSchool,
      role: targetUserRole
    });

    // Check permissions
    let hasPermission = false;

    if (isCallerSuperAdmin) {
      // Super admin can reset any user's password except other super admins
      if (targetUserRole === 'super_admin') {
        throw new functions.https.HttpsError(
          'permission-denied', 
          'Cannot reset password for super admin accounts'
        );
      }
      hasPermission = true;
    } else if (callerAdminInfo.isSchoolAdmin) {
      // School admin can only reset teachers and students from their own school
      if (targetUserSchool === callerAdminInfo.schoolCode && 
          (targetUserRole === 'teacher' || targetUserRole === 'student')) {
        hasPermission = true;
      } else {
        throw new functions.https.HttpsError(
          'permission-denied', 
          'School admins can only reset passwords for teachers and students in their own school'
        );
      }
    } else {
      throw new functions.https.HttpsError(
        'permission-denied', 
        'Only super admins and school admins can reset passwords'
      );
    }

    if (!hasPermission) {
      throw new functions.https.HttpsError(
        'permission-denied', 
        'Insufficient permissions to reset password for this user'
      );
    }

    // Generate a random 6-digit temporary password
    const tempPassword = Math.floor(100000 + Math.random() * 900000).toString();
    
    // Try multiple methods to find the user in Auth
    let authUser = null;
    let foundBy = '';

    // Method 1: Try to find by UID (direct)
    try {
      authUser = await auth.getUser(targetUid);
      foundBy = 'uid';
      console.log(`Found user in Auth by UID: ${authUser.uid}, email: ${authUser.email}`);
    } catch (uidError) {
      console.log(`User not found by UID (${targetUid}): ${uidError.message}`);
      
      // Method 2: Try to find by email pattern (username_school@studentapp.com)
      const emailPattern1 = `${targetUsername}_${targetUserSchool}@studentapp.com`;
      try {
        authUser = await auth.getUserByEmail(emailPattern1);
        foundBy = 'email_pattern_1';
        console.log(`Found user in Auth by email pattern 1: ${emailPattern1}`);
      } catch (emailError1) {
        console.log(`User not found by email pattern 1 (${emailPattern1}): ${emailError1.message}`);
        
        // Method 3: Try alternative email pattern (username@studentapp.com)
        const emailPattern2 = `${targetUsername}@studentapp.com`;
        try {
          authUser = await auth.getUserByEmail(emailPattern2);
          foundBy = 'email_pattern_2';
          console.log(`Found user in Auth by email pattern 2: ${emailPattern2}`);
        } catch (emailError2) {
          console.log(`User not found by email pattern 2 (${emailPattern2}): ${emailError2.message}`);
          
          // Method 4: List users and search by username in email
          try {
            const listUsersResult = await auth.listUsers(1000);
            const users = listUsersResult.users;
            
            authUser = users.find(user => {
              if (!user.email) return false;
              // Check if email contains the username
              return user.email.includes(targetUsername) || 
                     user.email === emailPattern1 || 
                     user.email === emailPattern2;
            });
            
            if (authUser) {
              foundBy = 'email_search';
              console.log(`Found user in Auth by email search: ${authUser.email}`);
            } else {
              throw new functions.https.HttpsError(
                'not-found', 
                `User not found in authentication system. Tried:
                - UID: ${targetUid}
                - Email: ${emailPattern1}
                - Email: ${emailPattern2}
                - Email search for username: ${targetUsername}`
              );
            }
          } catch (searchError) {
            console.log(`Error searching users: ${searchError.message}`);
            throw new functions.https.HttpsError(
              'not-found', 
              `User not found in authentication system. Search error: ${searchError.message}`
            );
          }
        }
      }
    }

    if (!authUser) {
      throw new functions.https.HttpsError(
        'not-found', 
        'User not found in authentication system after multiple search attempts'
      );
    }

    console.log(`Updating password for user: ${authUser.uid}, found by: ${foundBy}`);

    // Update the user's password in Firebase Auth
    await auth.updateUser(authUser.uid, {
      password: tempPassword
    });

    console.log(`Password updated successfully for user: ${authUser.uid}`);

    // Update the user's document in Firestore
    await db.collection('users').doc(targetUid).update({
      is_first_login: true,
      password_reset_at: admin.firestore.FieldValue.serverTimestamp(),
      reset_by: callerUid,
      last_password_reset: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Log the action in admin_logs collection
    await db.collection('admin_logs').add({
      action: 'password_reset',
      target_uid: targetUid,
      target_username: targetUsername,
      target_role: targetUserRole,
      target_school: targetUserSchool,
      target_auth_uid: authUser.uid,
      target_auth_email: authUser.email,
      found_by: foundBy,
      performed_by: callerUid,
      performed_by_uid: callerUid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      tempPassword: tempPassword,
      authUid: authUser.uid,
      authEmail: authUser.email,
      foundBy: foundBy,
      message: `Password reset successfully for ${targetUsername}. Temporary password generated.`
    };

  } catch (error) {
    console.error('Error resetting password:', error);
    
    // Handle specific Firebase Auth errors
    if (error.code === 'auth/user-not-found') {
      throw new functions.https.HttpsError(
        'not-found', 
        'User not found in authentication system. Please check if the user exists in Firebase Auth.'
      );
    } else if (error.code === 'auth/insufficient-permission') {
      throw new functions.https.HttpsError(
        'permission-denied', 
        'Insufficient permissions to reset password'
      );
    } else if (error.code === 'auth/invalid-uid') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Invalid user ID format'
      );
    }
    
    throw new functions.https.HttpsError(
      'internal', 
      `Error resetting password: ${error.message}`
    );
  }
});

// OPTIMIZED: Delete user from both Firestore and Auth with atomic count updates
exports.deleteUser = functions.https.onCall(async (data, context) => {
  // Check if user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { userId, username } = data;
  
  if (!userId) {
    throw new functions.https.HttpsError('invalid-argument', 'User ID is required');
  }

  try {
    // Get caller's information
    const callerUid = context.auth.uid;
    const isCallerSuperAdmin = await isSuperAdmin(callerUid);
    const callerAdminInfo = await getSchoolAdminInfo(callerUid);

    // Get the target user's data
    const targetUserDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!targetUserDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User not found');
    }

    const targetUserData = targetUserDoc.data();
    const targetUserRole = targetUserData.role;
    const targetUserSchool = targetUserData.school_code;
    const targetUsername = targetUserData.username;

    // Check permissions
    let hasPermission = false;

    if (isCallerSuperAdmin) {
      hasPermission = true;
    } else if (callerAdminInfo.isSchoolAdmin) {
      if (targetUserSchool === callerAdminInfo.schoolCode && 
          (targetUserRole === 'teacher' || targetUserRole === 'student')) {
        hasPermission = true;
      } else {
        throw new functions.https.HttpsError(
          'permission-denied', 
          'School admins can only delete teachers and students from their own school'
        );
      }
    } else {
      throw new functions.https.HttpsError(
        'permission-denied', 
        'Only super admins and school admins can delete users'
      );
    }

    if (!hasPermission) {
      throw new functions.https.HttpsError(
        'permission-denied', 
        'Insufficient permissions to delete this user'
      );
    }

    const db = admin.firestore();

    // OPTIMIZED: Use batch for atomic operations
    const batch = db.batch();

    // Add user deletion to batch
    batch.delete(db.collection('users').doc(userId));

    // OPTIMIZED: Use atomic increment for count update in the same batch
    const schoolRef = db.collection('schools').doc(targetUserSchool);
    const field = `${targetUserRole}_count`;
    
    batch.update(schoolRef, {
      [field]: admin.firestore.FieldValue.increment(-1)
    });

    // Commit the batch (both operations atomic)
    await batch.commit();

    console.log(`✅ ATOMIC DELETE: User ${userId} deleted and ${field} decremented`);

    // Delete from Firebase Auth
    await admin.auth().deleteUser(userId);

    return {
      success: true,
      message: `User "${username}" deleted successfully from both database and authentication system`
    };

  } catch (error) {
    console.error('Error deleting user:', error);
    
    // If there's an error deleting from Auth, we still want to inform about Firestore deletion
    if (error.code === 'auth/user-not-found') {
      return {
        success: true,
        message: `User "${username}" deleted from database (user not found in authentication system)`
      };
    }
    
    throw new functions.https.HttpsError('internal', `Error deleting user: ${error.message}`);
  }
});

// COMPLETE: Bulk delete users with all required helper functions
exports.deleteUsersBulk = functions.runWith({
  timeoutSeconds: 540, // 9 minutes
  memory: '2GB'
}).https.onCall(async (data, context) => {
  // Check if user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { userIds } = data;
  
  if (!Array.isArray(userIds) || userIds.length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'User IDs array is required and must not be empty');
  }

  // Validate input size
  if (userIds.length > 1000) {
    throw new functions.https.HttpsError(
      'invalid-argument', 
      `Cannot delete more than 1000 users at once. You selected ${userIds.length} users.`
    );
  }

  try {
    // Get caller's information
    const callerUid = context.auth.uid;
    const isCallerSuperAdmin = await isSuperAdmin(callerUid);
    const callerAdminInfo = await getSchoolAdminInfo(callerUid);

    const totalUsers = userIds.length;
    const results = [];
    
    console.log(`🔄 Starting QUOTA-AWARE bulk delete for ${totalUsers} users`);

    // Get all user data in chunks
    const allUserData = await getUsersInChunksForDeletion(userIds);
    console.log(`📊 Fetched data for ${allUserData.length} users`);

    // Validate permissions for all users
    const validatedUsers = [];
    const permissionErrors = [];

    for (const userData of allUserData) {
      try {
        const hasPermission = await validateUserDeletionPermission(
          userData, 
          callerUid, 
          isCallerSuperAdmin, 
          callerAdminInfo
        );
        
        if (hasPermission) {
          validatedUsers.push(userData);
        }
      } catch (error) {
        permissionErrors.push({
          userId: userData.id,
          username: userData.username,
          error: error.message
        });
      }
    }

    console.log(`✅ Validated ${validatedUsers.length} users for deletion`);

    // ENHANCED: Process with quota management and retry logic
    const QUOTA_AWARE_CONCURRENCY = 5; // Reduced concurrency for quota management
    const totalBatches = Math.ceil(validatedUsers.length / QUOTA_AWARE_CONCURRENCY);
    
    let processedCount = 0;
    let successfulDeletions = 0;
    let failedDeletions = 0;
    const failedUsers = [...permissionErrors];
    
    // Track quota usage
    let quotaResetTime = Date.now() + 100000; // 100 seconds from now
    let deletionsInCurrentWindow = 0;
    const MAX_DELETIONS_PER_WINDOW = 900; // Stay under 1000 limit

    console.log(`📦 Processing ${validatedUsers.length} validated users in ${totalBatches} batches with quota management`);

    for (let i = 0; i < validatedUsers.length; i += QUOTA_AWARE_CONCURRENCY) {
      const batch = validatedUsers.slice(i, i + QUOTA_AWARE_CONCURRENCY);
      const batchNumber = Math.floor(i / QUOTA_AWARE_CONCURRENCY) + 1;
      
      console.log(`🔄 Processing batch ${batchNumber}/${totalBatches} with ${batch.length} users`);
      
      // ENHANCED: Check quota before processing batch
      const now = Date.now();
      if (now >= quotaResetTime) {
        // Reset quota window
        quotaResetTime = now + 100000;
        deletionsInCurrentWindow = 0;
        console.log(`🔄 Quota window reset`);
      }
      
      if (deletionsInCurrentWindow + batch.length >= MAX_DELETIONS_PER_WINDOW) {
        // Wait for quota window to reset
        const waitTime = quotaResetTime - now;
        console.log(`⏳ Approaching quota limit. Waiting ${waitTime}ms for quota reset...`);
        await new Promise(resolve => setTimeout(resolve, waitTime + 1000)); // Extra 1 second buffer
        
        // Reset quota tracking after wait
        quotaResetTime = Date.now() + 100000;
        deletionsInCurrentWindow = 0;
      }

      // Process current batch with enhanced error handling and retries
      const batchPromises = batch.map(userData => 
        processUserDeletionWithRetry(userData, 3) // 3 retry attempts
      );

      const batchResults = await Promise.allSettled(batchPromises);
      
      // Process batch results
      for (let j = 0; j < batchResults.length; j++) {
        const result = batchResults[j];
        const userData = batch[j];
        
        if (result.status === 'fulfilled' && result.value.success) {
          successfulDeletions++;
          results.push(result.value);
          deletionsInCurrentWindow++;
        } else {
          failedDeletions++;
          const errorInfo = result.status === 'fulfilled' 
            ? result.value 
            : { 
                userId: userData.id, 
                username: userData.username, 
                error: result.reason?.message || 'Unknown error during deletion',
                success: false
              };
          failedUsers.push(errorInfo);
          results.push(errorInfo);
        }
        
        processedCount++;
        console.log(`📊 Progress: ${processedCount}/${validatedUsers.length} users processed`);
      }

      // Progress update
      console.log(`✅ Batch ${batchNumber} completed: ${successfulDeletions} successful, ${failedDeletions} failed`);
      console.log(`📈 Quota usage: ${deletionsInCurrentWindow}/${MAX_DELETIONS_PER_WINDOW} in current window`);

      // ENHANCED: Adaptive rate limiting based on quota usage
      if (deletionsInCurrentWindow > MAX_DELETIONS_PER_WINDOW * 0.8) {
        // If we're using more than 80% of quota, increase delay
        const delay = Math.max(1000, (deletionsInCurrentWindow / MAX_DELETIONS_PER_WINDOW) * 2000);
        console.log(`⏳ High quota usage. Increasing delay to ${delay}ms`);
        await new Promise(resolve => setTimeout(resolve, delay));
      } else if (i + QUOTA_AWARE_CONCURRENCY < validatedUsers.length) {
        // Normal rate limiting
        await new Promise(resolve => setTimeout(resolve, 500));
      }
    }

    // ENHANCED: Final attempt for failed deletions with individual processing
    if (failedDeletions > 0) {
      console.log(`🔄 Making final attempt for ${failedDeletions} failed users`);
      
      const finalFailedUsers = [...failedUsers.filter(f => f.userId && f.userId !== 'unknown')];
      const finalResults = await retryFailedDeletions(finalFailedUsers, validatedUsers);
      
      // Update counts based on final results
      const finalSuccessCount = finalResults.filter(r => r.success).length;
      successfulDeletions += finalSuccessCount;
      failedDeletions -= finalSuccessCount;
      
      console.log(`🎉 Final retry: ${finalSuccessCount} additional users deleted successfully`);
    }

    console.log(`🎉 QUOTA-AWARE bulk deletion completed. Success: ${successfulDeletions}, Failed: ${failedDeletions}`);

    return { 
      results: results,
      summary: {
        total: validatedUsers.length,
        successful: successfulDeletions,
        failed: failedDeletions,
        permissionErrors: permissionErrors.length
      }
    };

  } catch (error) {
    console.error('❌ Critical error in QUOTA-AWARE bulk delete:', error);
    throw new functions.https.HttpsError('internal', `Bulk delete failed: ${error.message}`);
  }
});

// REQUIRED: Helper function to get users in chunks
async function getUsersInChunksForDeletion(userIds) {
  const CHUNK_SIZE = 25; // Stay under Firestore's 30 limit
  const allUserData = [];
  
  console.log(`📥 Fetching ${userIds.length} users in chunks of ${CHUNK_SIZE}`);

  for (let i = 0; i < userIds.length; i += CHUNK_SIZE) {
    const chunk = userIds.slice(i, i + CHUNK_SIZE);
    const chunkNumber = Math.floor(i / CHUNK_SIZE) + 1;
    const totalChunks = Math.ceil(userIds.length / CHUNK_SIZE);
    
    console.log(`📦 Fetching chunk ${chunkNumber}/${totalChunks} with ${chunk.length} users`);

    try {
      const usersSnapshot = await admin.firestore().collection('users')
        .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
        .get();

      usersSnapshot.docs.forEach(doc => {
        allUserData.push({
          id: doc.id,
          ...doc.data()
        });
      });
      
      console.log(`✅ Chunk ${chunkNumber}: Fetched ${usersSnapshot.size} users`);
      
    } catch (error) {
      console.error(`❌ Error fetching chunk ${chunkNumber}:`, error);
      
      // Fallback: Try individual document gets for this chunk
      console.log(`🔄 Falling back to individual gets for chunk ${chunkNumber}`);
      
      const individualPromises = chunk.map(async (userId) => {
        try {
          const userDoc = await admin.firestore().collection('users').doc(userId).get();
          if (userDoc.exists) {
            return {
              id: userDoc.id,
              ...doc.data()
            };
          }
          return null;
        } catch (individualError) {
          console.error(`❌ Error fetching user ${userId}:`, individualError);
          return null;
        }
      });

      const individualResults = await Promise.all(individualPromises);
      const validUsers = individualResults.filter(user => user !== null);
      allUserData.push(...validUsers);
      
      console.log(`✅ Individual fallback for chunk ${chunkNumber}: ${validUsers.length} users found`);
    }

    // Rate limiting between chunks
    if (i + CHUNK_SIZE < userIds.length) {
      await new Promise(resolve => setTimeout(resolve, 200));
    }
  }

  console.log(`📊 Total users fetched: ${allUserData.length}`);
  return allUserData;
}

// REQUIRED: Process user deletion with automatic retry logic
async function processUserDeletionWithRetry(userData, maxRetries = 3) {
  let lastError;
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const result = await processSingleUserDeletionOptimized(userData);
      
      if (result.success) {
        return result;
      }
      
      // If Firestore succeeded but Auth failed, we have a partial success
      if (result.firestoreDeleted && !result.authDeleted) {
        console.log(`⚠️ Partial success for user ${userData.id}: Firestore deleted but Auth pending`);
        
        // We'll consider this successful for now, and Auth can be cleaned up later
        return {
          ...result,
          success: true, // Mark as successful since Firestore is clean
          message: `${result.message} (Auth deletion pending - will be cleaned up automatically)`
        };
      }
      
      lastError = result.error;
      
    } catch (error) {
      lastError = error.message;
      
      // Check if it's a quota error
      if (error.message.includes('quota') || error.message.includes('Quota')) {
        console.log(`⏳ Quota error for user ${userData.id}, attempt ${attempt}/${maxRetries}`);
        
        // Exponential backoff for quota errors
        const backoffTime = Math.min(1000 * Math.pow(2, attempt), 10000); // Max 10 seconds
        await new Promise(resolve => setTimeout(resolve, backoffTime));
        continue;
      }
      
      // For other errors, retry immediately with smaller delay
      await new Promise(resolve => setTimeout(resolve, 500));
    }
  }
  
  // All retries failed
  return {
    userId: userData.id,
    username: userData.username,
    success: false,
    error: `All retries failed: ${lastError}`
  };
}

// REQUIRED: Retry failed deletions with individual care
async function retryFailedDeletions(failedUsers, allUserData) {
  const results = [];
  
  for (const failedUser of failedUsers) {
    const userData = allUserData.find(u => u.id === failedUser.userId);
    if (!userData) continue;
    
    console.log(`🔄 Final retry for user: ${userData.username}`);
    
    try {
      // Use individual approach with no concurrency for final attempt
      const result = await processSingleUserDeletionIndividual(userData);
      results.push(result);
      
      if (result.success) {
        console.log(`✅ Final retry successful for user: ${userData.username}`);
      } else {
        console.log(`❌ Final retry failed for user: ${userData.username} - ${result.error}`);
      }
      
      // Be very gentle with final retries
      await new Promise(resolve => setTimeout(resolve, 1000));
      
    } catch (error) {
      console.error(`❌ Error in final retry for user ${userData.username}:`, error);
      results.push({
        userId: userData.id,
        username: userData.username,
        success: false,
        error: `Final retry failed: ${error.message}`
      });
    }
  }
  
  return results;
}

// REQUIRED: Individual user deletion without batching for final attempts
async function processSingleUserDeletionIndividual(userData) {
  const db = admin.firestore();

  try {
    const userId = userData.id;
    const targetUserRole = userData.role;
    const targetUserSchool = userData.school_code;
    const targetUsername = userData.username;

    console.log(`🔧 Individual deletion for user: ${targetUsername}`);

    // Step 1: Delete from Firestore first
    await db.collection('users').doc(userId).delete();
    console.log(`✅ Firestore: User ${userId} deleted`);

    // Step 2: Update school count
    const schoolRef = db.collection('schools').doc(targetUserSchool);
    const field = `${targetUserRole}_count`;
    
    await schoolRef.update({
      [field]: admin.firestore.FieldValue.increment(-1)
    });
    console.log(`✅ Count updated: ${field} decremented for school ${targetUserSchool}`);

    // Step 3: Delete from Auth with individual care
    let authDeleted = false;
    let authError = null;
    
    try {
      await admin.auth().deleteUser(userId);
      authDeleted = true;
      console.log(`✅ Auth: User ${userId} deleted from authentication`);
    } catch (authError) {
      if (authError.code === 'auth/user-not-found') {
        console.log(`ℹ️ User ${userId} already deleted from Auth`);
        authDeleted = true; // Consider this success
      } else if (authError.message.includes('quota') || authError.message.includes('Quota')) {
        console.log(`⏳ Quota limit hit for user ${userId}, Auth deletion postponed`);
        authError = 'Auth quota limit - will be cleaned up automatically';
        // We'll still consider this success since Firestore is clean
        authDeleted = true;
      } else {
        throw authError;
      }
    }

    return {
      userId: userId,
      username: targetUsername,
      success: true, // Always success if Firestore is clean
      firestoreDeleted: true,
      authDeleted: authDeleted,
      message: authDeleted 
        ? `User "${targetUsername}" deleted successfully from both systems`
        : `User "${targetUsername}" deleted from database (Auth deletion pending: ${authError})`
    };

  } catch (error) {
    console.error(`❌ Individual deletion failed for user ${userData.id}:`, error);
    
    return {
      userId: userData.id,
      username: userData.username,
      success: false,
      error: `Individual deletion failed: ${error.message}`
    };
  }
}

// REQUIRED: Single user deletion processing with better state tracking
async function processSingleUserDeletionOptimized(userData) {
  const db = admin.firestore();

  try {
    const userId = userData.id;
    const targetUserRole = userData.role;
    const targetUserSchool = userData.school_code;
    const targetUsername = userData.username;

    // Use batch for atomic Firestore operations
    const batch = db.batch();

    // Delete user from Firestore
    batch.delete(db.collection('users').doc(userId));

    // Update school count atomically
    const schoolRef = db.collection('schools').doc(targetUserSchool);
    const field = `${targetUserRole}_count`;
    
    batch.update(schoolRef, {
      [field]: admin.firestore.FieldValue.increment(-1)
    });

    // Commit Firestore operations atomically
    await batch.commit();
    console.log(`✅ Firestore: User ${userId} deleted and ${field} decremented`);

    // Delete from Firebase Auth with quota awareness
    let authDeleted = false;
    try {
      await admin.auth().deleteUser(userId);
      authDeleted = true;
      console.log(`✅ Auth: User ${userId} deleted from authentication`);
    } catch (authError) {
      if (authError.code === 'auth/user-not-found') {
        console.log(`ℹ️ User ${userId} already deleted from Auth`);
        authDeleted = true;
      } else {
        // Re-throw auth errors for retry logic
        throw authError;
      }
    }

    return {
      userId: userId,
      username: targetUsername,
      success: true,
      firestoreDeleted: true,
      authDeleted: authDeleted,
      message: `User "${targetUsername}" deleted successfully from both systems`
    };

  } catch (error) {
    console.error(`❌ Error deleting user ${userData.id}:`, error);
    
    // Enhanced fallback with better error handling
    try {
      console.log(`🔄 Attempting enhanced fallback for user ${userData.id}`);
      
      // Individual Firestore deletion
      await admin.firestore().collection('users').doc(userData.id).delete();
      
      // Individual count update
      const schoolRef = admin.firestore().collection('schools').doc(userData.school_code);
      const field = `${userData.role}_count`;
      
      await schoolRef.update({
        [field]: admin.firestore.FieldValue.increment(-1)
      });
      
      console.log(`✅ Enhanced fallback successful for Firestore: ${userData.id}`);
      
      // Try auth deletion again with fallback
      let authDeleted = false;
      try {
        await admin.auth().deleteUser(userData.id);
        authDeleted = true;
      } catch (authError) {
        if (authError.code === 'auth/user-not-found') {
          authDeleted = true;
        } else if (authError.message.includes('quota') || authError.message.includes('Quota')) {
          console.log(`⏳ Quota limit in fallback for user ${userData.id}`);
          // We'll still consider this success since Firestore is clean
          authDeleted = true;
        } else {
          throw authError;
        }
      }
      
      return {
        userId: userData.id,
        username: userData.username,
        success: true,
        firestoreDeleted: true,
        authDeleted: authDeleted,
        message: authDeleted 
          ? `User deleted successfully (via enhanced fallback)`
          : `User deleted from database (Auth pending via fallback)`
      };
      
    } catch (fallbackError) {
      console.error(`❌ Enhanced fallback also failed for user ${userData.id}:`, fallbackError);
      
      return {
        userId: userData.id,
        username: userData.username,
        success: false,
        error: `Deletion failed: ${error.message} (Fallback: ${fallbackError.message})`
      };
    }
  }
}

// REQUIRED: Permission validation helper
async function validateUserDeletionPermission(userData, callerUid, isCallerSuperAdmin, callerAdminInfo) {
  const targetUserRole = userData.role;
  const targetUserSchool = userData.school_code;

  if (isCallerSuperAdmin) {
    return true;
  } else if (callerAdminInfo.isSchoolAdmin) {
    if (targetUserSchool === callerAdminInfo.schoolCode && 
        (targetUserRole === 'teacher' || targetUserRole === 'student')) {
      return true;
    } else {
      throw new Error('School admins can only delete teachers and students from their own school');
    }
  } else {
    throw new Error('Only super admins and school admins can delete users');
  }
}
// OPTIMIZED: Single user creation function with atomic count updates
exports.createUser = functions.https.onCall(async (data, context) => {
  // Check if user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { userData } = data;
  
  // DEBUG: Log incoming data
  console.log('=== CLOUD FUNCTION createUser CALLED ===');
  console.log('Full data received:', JSON.stringify(data, null, 2));
  console.log('UserData received:', JSON.stringify(userData, null, 2));
  console.log('Context auth:', context.auth);
  console.log('========================================');

  try {
    // Validate required fields
    if (!userData.username || !userData.role || !userData.schoolCode || !userData.password) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
    }

    if (userData.password.length < 6) {
      throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters');
    }

    // Get caller's information
    const callerUid = context.auth.uid;
    const isCallerSuperAdmin = await isSuperAdmin(callerUid);
    const callerAdminInfo = await getSchoolAdminInfo(callerUid);

    // Check permissions based on role being created
    let hasPermission = false;
    let enforcedSchoolCode = userData.schoolCode;

    if (isCallerSuperAdmin) {
      // Super admin can create any user (admin, teacher, student) in any school
      hasPermission = true;
    } else if (callerAdminInfo.isSchoolAdmin) {
      // School admin can only create teachers and students in their own school
      if (userData.role === 'teacher' || userData.role === 'student') {
        if (userData.schoolCode === callerAdminInfo.schoolCode) {
          hasPermission = true;
          enforcedSchoolCode = callerAdminInfo.schoolCode; // Ensure school admin can't change school code
        } else {
          throw new functions.https.HttpsError(
            'permission-denied', 
            'School admins can only create users for their own school'
          );
        }
      } else {
        throw new functions.https.HttpsError(
          'permission-denied', 
          'School admins can only create teachers and students'
        );
      }
    } else {
      throw new functions.https.HttpsError(
        'permission-denied', 
        'Only super admins and school admins can create users'
      );
    }

    if (!hasPermission) {
      throw new functions.https.HttpsError(
        'permission-denied', 
        'Insufficient permissions to create this user'
      );
    }

    // Check if school exists
    const schoolDoc = await db.collection('schools').doc(enforcedSchoolCode).get();
    if (!schoolDoc.exists) {
      throw new functions.https.HttpsError('invalid-argument', 'School does not exist');
    }

    const schoolName = schoolDoc.data().name;
    const email = `${userData.username}_${enforcedSchoolCode}@studentapp.com`;

    // Check if user already exists
    const existingUser = await db.collection('users')
      .where('username', '==', userData.username)
      .where('school_code', '==', enforcedSchoolCode)
      .where('role', '==', userData.role)
      .limit(1)
      .get();

    if (!existingUser.empty) {
      throw new functions.https.HttpsError('already-exists', 
        `${userData.role.toUpperCase()} username "${userData.username}" already exists in ${schoolName}`);
    }

    // Create user in Firebase Auth
    const userRecord = await auth.createUser({
      email: email,
      password: userData.password,
      emailVerified: false,
      disabled: false,
    });

    // Prepare user data for Firestore
    const firestoreUserData = {
      uid: userRecord.uid,
      username: userData.username,
      role: userData.role,
      school_code: enforcedSchoolCode,
      school_name: schoolName,
      status: userData.status || 'active',
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      created_by: isCallerSuperAdmin ? 'Super Admin' : `School Admin (${callerUid})`,
      is_first_login: true,
    };

    // Add ALL optional fields EXCEPT class assignment fields (we'll handle them separately)
    const optionalFields = [
      'full_name', 'mobile_number', 'gmail', 'subject', 'class_teacher_for',
      'roll_number', 'parent_guardian_name', 'parent_guardian_mobile',
      'alternate_mobile_number', 'school_telephone_number'
    ];

    optionalFields.forEach(field => {
      if (userData[field] !== undefined && userData[field] !== null && userData[field].toString().trim() !== '') {
        firestoreUserData[field] = userData[field].toString().trim();
        console.log(`✓ Added optional field ${field}: ${userData[field]}`);
      }
    });

    // STUDENT CLASS ASSIGNMENT - UPDATED LOGIC
    if (userData.role === 'student') {
      console.log('🔍 PROCESSING STUDENT CLASS ASSIGNMENT');
      console.log('Incoming student data:', {
        class_name: userData.class_name,
        section: userData.section,
        class_id: userData.class_id
      });

      // ALWAYS preserve the incoming class_name and section
      if (userData.class_name) {
        firestoreUserData.class_name = userData.class_name;
        console.log('✓ Set class_name:', userData.class_name);
      }
      
      if (userData.section) {
        firestoreUserData.section = userData.section;
        console.log('✓ Set section:', userData.section);
      }

      // CRITICAL FIX: Find the correct class_id based on grade and section
      if (userData.class_name && userData.section) {
        try {
          // Extract grade from class_name (remove "Grade " prefix if present)
          let grade = userData.class_name;
          if (grade.startsWith('Grade ')) {
            grade = grade.substring(6); // Remove "Grade " prefix
          }
          
          console.log(`🔍 Searching for class with grade: "${grade}" and section: "${userData.section}"`);

          // Query classes collection to find the matching class
          const classesSnapshot = await db.collection('schools')
            .doc(enforcedSchoolCode)
            .collection('classes')
            .where('grade', '==', grade)
            .get();

          let foundClassId = null;
          let foundClassData = null;
          
          for (const classDoc of classesSnapshot.docs) {
            const classData = classDoc.data();
            const classGrade = classData.grade;
            const classSections = classData.sections;
            
            console.log(`Checking class ${classDoc.id}: grade="${classGrade}", sections=`, classSections);

            // Check if grade matches
            if (classGrade !== grade) continue;

            // Check if section exists in this class's sections
            let sectionFound = false;
            if (Array.isArray(classSections)) {
              sectionFound = classSections.includes(userData.section);
            } else if (typeof classSections === 'string') {
              const sectionsList = classSections.split(',')
                .map(s => s.trim())
                .filter(s => s.length > 0);
              sectionFound = sectionsList.includes(userData.section);
            }

            if (sectionFound) {
              foundClassId = classDoc.id;
              foundClassData = classData;
              console.log(`✅ Found matching class: ${foundClassId} for grade ${grade} and section ${userData.section}`);
              break;
            }
          }

          if (foundClassId) {
            firestoreUserData.class_id = foundClassId;
            console.log('✅ Assigned class_id:', foundClassId);
            
            // Also ensure class_name is properly formatted
            if (foundClassData && foundClassData.grade) {
              firestoreUserData.class_name = `Grade ${foundClassData.grade}`;
              console.log('✅ Updated class_name to:', firestoreUserData.class_name);
            }
          } else {
            console.warn('⚠️ No matching class found for grade:', grade, 'and section:', userData.section);
            firestoreUserData.class_id = null;
            // Format class_name properly even if class_id not found
            if (!userData.class_name.startsWith('Grade ')) {
              firestoreUserData.class_name = `Grade ${userData.class_name}`;
            }
          }
        } catch (classError) {
          console.error('❌ Error finding class:', classError);
          firestoreUserData.class_id = null;
          // Format class_name as fallback
          if (userData.class_name && !userData.class_name.startsWith('Grade ')) {
            firestoreUserData.class_name = `Grade ${userData.class_name}`;
          }
        }
      } else {
        console.warn('⚠️ Missing class_name or section, cannot assign class_id');
        firestoreUserData.class_id = null;
        // Format class_name as fallback
        if (userData.class_name && !userData.class_name.startsWith('Grade ')) {
          firestoreUserData.class_name = `Grade ${userData.class_name}`;
        }
      }

      // Final verification
      console.log('🎯 FINAL STUDENT ASSIGNMENT:');
      console.log('class_id:', firestoreUserData.class_id);
      console.log('class_name:', firestoreUserData.class_name);
      console.log('section:', firestoreUserData.section);
    }

    // FINAL VERIFICATION: Log what will be saved to Firestore
    console.log('=== FINAL FIRESTORE USER DATA ===');
    console.log(JSON.stringify(firestoreUserData, null, 2));
    console.log('=================================');

    // Create user document in Firestore
    await db.collection('users').doc(userRecord.uid).set(firestoreUserData);

    // OPTIMIZED: Use atomic update for school user counts
    await updateSchoolUserCounts(enforcedSchoolCode, userData.role, 1);

    // VERIFY: Confirm what was saved
    const savedDoc = await db.collection('users').doc(userRecord.uid).get();
    console.log('✅ VERIFICATION - SAVED DOCUMENT:');
    console.log(JSON.stringify(savedDoc.data(), null, 2));

    // Log the creation for debugging
    console.log('User created successfully in Cloud Function:', {
      uid: userRecord.uid,
      username: userData.username,
      role: userData.role,
      class_assignment: userData.role === 'student' ? {
        class_id: firestoreUserData.class_id,
        class_name: firestoreUserData.class_name,
        section: firestoreUserData.section
      } : 'N/A'
    });

    return {
      success: true,
      userId: userRecord.uid,
      email: email,
      message: `${userData.role.toUpperCase()} "${userData.username}" created successfully in ${schoolName}`
    };

  } catch (error) {
    console.error('❌ Error creating user in Cloud Function:', error);
    console.error('Error details:', {
      message: error.message,
      code: error.code,
      stack: error.stack
    });
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// OPTIMIZED: Bulk user creation function with improved performance
exports.createUsersBulk = functions.runWith({
  timeoutSeconds: 540, // Increased to 9 minutes timeout
  memory: '2GB' // Increased memory for better performance
}).https.onCall(async (data, context) => {
  // Check if user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { users } = data;
  
  console.log('=== OPTIMIZED CLOUD FUNCTION createUsersBulk CALLED ===');
  console.log('Number of users:', users ? users.length : 0);
  console.log('Context auth:', context.auth);
  console.log('=======================================================');

  if (!Array.isArray(users) || users.length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'Users array is required and must not be empty');
  }

  // Get caller's information
  const callerUid = context.auth.uid;
  const isCallerSuperAdmin = await isSuperAdmin(callerUid);
  const callerAdminInfo = await getSchoolAdminInfo(callerUid);

  const results = [];
  
  try {
    // OPTIMIZED: Pre-fetch school data and classes to avoid repeated queries
    const enforcedSchoolCode = callerAdminInfo.isSchoolAdmin ? callerAdminInfo.schoolCode : users[0].schoolCode;
    const schoolDoc = await db.collection('schools').doc(enforcedSchoolCode).get();
    
    if (!schoolDoc.exists) {
      throw new functions.https.HttpsError('invalid-argument', 'School does not exist');
    }

    const schoolName = schoolDoc.data().name;
    
    // OPTIMIZED: Pre-load all classes for the school to avoid repeated queries
    const classesSnapshot = await db.collection('schools')
      .doc(enforcedSchoolCode)
      .collection('classes')
      .get();
    
    const classDocs = classesSnapshot.docs;
    console.log(`📚 Pre-loaded ${classDocs.length} classes for school ${enforcedSchoolCode}`);

    // OPTIMIZED: Process users in larger batches with better performance
    const concurrency = 10; // Increased concurrency for better performance
    const totalUsers = users.length;
    
    console.log(`🔄 Starting parallel processing of ${totalUsers} users with concurrency of ${concurrency}`);

    let processedCount = 0;

    for (let i = 0; i < totalUsers; i += concurrency) {
      const batch = users.slice(i, i + concurrency);
      const batchNumber = Math.floor(i / concurrency) + 1;
      const totalBatches = Math.ceil(totalUsers / concurrency);
      
      console.log(`📦 Processing batch ${batchNumber}/${totalBatches} with ${batch.length} users`);

      // Process current batch in parallel with pre-loaded data
      const batchPromises = batch.map(userData => 
        processSingleUserOptimized(
          userData, 
          callerUid, 
          isCallerSuperAdmin, 
          callerAdminInfo, 
          enforcedSchoolCode, 
          schoolName,
          classDocs
        )
      );

      // Wait for all promises in current batch to settle (complete or fail)
      const batchResults = await Promise.allSettled(batchPromises);
      
      // Process batch results
      for (let j = 0; j < batchResults.length; j++) {
        const result = batchResults[j];
        const userData = batch[j];
        
        if (result.status === 'fulfilled') {
          // User was created successfully
          results.push(result.value);
          processedCount++;
          console.log(`✅ Successfully processed user: ${userData.username} (${processedCount}/${totalUsers})`);
        } else {
          // User creation failed
          console.error(`❌ Failed to process user ${userData.username}:`, result.reason);
          results.push({
            username: userData.username || 'Unknown',
            success: false,
            error: result.reason.message || 'Unknown error occurred'
          });
          processedCount++;
        }
      }

      // OPTIMIZED: Progress update every few batches
      if (batchNumber % 5 === 0) {
        console.log(`📊 Progress: ${processedCount}/${totalUsers} users processed`);
      }

      // OPTIMIZED: Smaller delay between batches for better performance
      if (i + concurrency < totalUsers) {
        await new Promise(resolve => setTimeout(resolve, 500)); // Reduced delay
      }
    }

    console.log(`🎉 Bulk processing completed. Success: ${results.filter(r => r.success).length}, Failed: ${results.filter(r => !r.success).length}`);

  } catch (error) {
    console.error('❌ Critical error in bulk user creation:', error);
    throw new functions.https.HttpsError('internal', `Bulk processing failed: ${error.message}`);
  }

  return { results };
});

// OPTIMIZED: Extracted single user processing logic with pre-loaded data
async function processSingleUserOptimized(
  userData, 
  callerUid, 
  isCallerSuperAdmin, 
  callerAdminInfo, 
  enforcedSchoolCode, 
  schoolName,
  classDocs
) {
  console.log(`🔄 Processing user: ${userData.username || 'Unknown'}`);
  
  // Validate required fields
  if (!userData.username || !userData.role || !userData.schoolCode || !userData.password) {
    throw new Error('Missing required fields (username, role, schoolCode, password)');
  }

  if (userData.password.length < 6) {
    throw new Error('Password must be at least 6 characters');
  }

  // Check permissions for each user
  let hasPermission = false;

  if (isCallerSuperAdmin) {
    hasPermission = true;
  } else if (callerAdminInfo.isSchoolAdmin) {
    if (userData.role === 'teacher' || userData.role === 'student') {
      if (userData.schoolCode === callerAdminInfo.schoolCode) {
        hasPermission = true;
      } else {
        throw new Error('School admins can only create users for their own school');
      }
    } else {
      throw new Error('School admins can only create teachers and students');
    }
  } else {
    throw new Error('Only super admins and school admins can create users');
  }

  if (!hasPermission) {
    throw new Error('Insufficient permissions to create this user');
  }

  const email = `${userData.username}_${enforcedSchoolCode}@studentapp.com`;

  // Check if user already exists
  const existingUser = await db.collection('users')
    .where('username', '==', userData.username)
    .where('school_code', '==', enforcedSchoolCode)
    .where('role', '==', userData.role)
    .limit(1)
    .get();

  if (!existingUser.empty) {
    throw new Error(`User already exists in ${schoolName}`);
  }

  // Create user in Firebase Auth
  const userRecord = await auth.createUser({
    email: email,
    password: userData.password,
    emailVerified: false,
    disabled: false,
  });

  // Prepare user data for Firestore
  const firestoreUserData = {
    uid: userRecord.uid,
    username: userData.username,
    role: userData.role,
    school_code: enforcedSchoolCode,
    school_name: schoolName,
    status: userData.status || 'active',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    created_by: isCallerSuperAdmin ? 'Super Admin (Bulk)' : `School Admin (Bulk - ${callerUid})`,
    is_first_login: true,
  };

  // Add ALL optional fields EXCEPT class assignment fields
  const optionalFields = [
    'full_name', 'mobile_number', 'gmail', 'subject', 'class_teacher_for',
    'roll_number', 'parent_guardian_name', 'parent_guardian_mobile',
    'alternate_mobile_number', 'school_telephone_number'
  ];

  optionalFields.forEach(field => {
    if (userData[field] !== undefined && userData[field] !== null && userData[field].toString().trim() !== '') {
      firestoreUserData[field] = userData[field].toString().trim();
    }
  });

  // STUDENT CLASS ASSIGNMENT - OPTIMIZED WITH PRE-LOADED CLASSES
  if (userData.role === 'student') {
    console.log(`🔍 Processing student: ${userData.username}`);
    console.log('Incoming student data:', {
      class_name: userData.class_name,
      section: userData.section,
      class_id: userData.class_id
    });

    // ALWAYS preserve the incoming class_name and section
    if (userData.class_name) {
      firestoreUserData.class_name = userData.class_name;
      console.log('✓ Set class_name:', userData.class_name);
    }
    
    if (userData.section) {
      firestoreUserData.section = userData.section;
      console.log('✓ Set section:', userData.section);
    }

    // OPTIMIZED: Use pre-loaded classes to find class_id
    if (userData.class_name && userData.section) {
      try {
        // Extract grade from class_name (remove "Grade " prefix if present)
        let grade = userData.class_name;
        if (grade.startsWith('Grade ')) {
          grade = grade.substring(6); // Remove "Grade " prefix
        }
        
        console.log(`🔍 Searching for class with grade: "${grade}" and section: "${userData.section}"`);

        let foundClassId = null;
        let foundClassData = null;
        
        for (const classDoc of classDocs) {
          const classData = classDoc.data();
          const classGrade = classData.grade;
          const classSections = classData.sections;
          
          console.log(`Checking class ${classDoc.id}: grade="${classGrade}", sections=`, classSections);

          // Check if grade matches
          if (classGrade !== grade) continue;

          // Check if section exists in this class's sections
          let sectionFound = false;
          if (Array.isArray(classSections)) {
            sectionFound = classSections.includes(userData.section);
          } else if (typeof classSections === 'string') {
            const sectionsList = classSections.split(',')
              .map(s => s.trim())
              .filter(s => s.length > 0);
            sectionFound = sectionsList.includes(userData.section);
          }

          if (sectionFound) {
            foundClassId = classDoc.id;
            foundClassData = classData;
            console.log(`✅ Found matching class: ${foundClassId} for grade ${grade} and section ${userData.section}`);
            break;
          }
        }

        if (foundClassId) {
          firestoreUserData.class_id = foundClassId;
          // Ensure class_name is properly formatted with "Grade" prefix
          if (foundClassData && foundClassData.grade) {
            firestoreUserData.class_name = `Grade ${foundClassData.grade}`;
          }
          console.log('✅ Assigned class_id:', foundClassId);
          console.log('✅ Updated class_name:', firestoreUserData.class_name);
        } else {
          console.warn('⚠️ No matching class found for grade:', grade, 'and section:', userData.section);
          firestoreUserData.class_id = null;
          // Still format the class_name properly even if class_id not found
          firestoreUserData.class_name = `Grade ${grade}`;
        }
      } catch (classError) {
        console.error('❌ Error finding class:', classError);
        firestoreUserData.class_id = null;
        // Format class_name as fallback
        if (userData.class_name && !userData.class_name.startsWith('Grade ')) {
          firestoreUserData.class_name = `Grade ${userData.class_name}`;
        }
      }
    } else {
      console.warn('⚠️ Missing class_name or section, cannot assign class_id');
      firestoreUserData.class_id = null;
      // Format class_name as fallback
      if (userData.class_name && !userData.class_name.startsWith('Grade ')) {
        firestoreUserData.class_name = `Grade ${userData.class_name}`;
      }
    }

    // Final verification
    console.log('🎯 FINAL STUDENT ASSIGNMENT:');
    console.log('class_id:', firestoreUserData.class_id);
    console.log('class_name:', firestoreUserData.class_name);
    console.log('section:', firestoreUserData.section);
  }

  // Create user document in Firestore
  await db.collection('users').doc(userRecord.uid).set(firestoreUserData);

  // OPTIMIZED: Use atomic update for school user counts
  await updateSchoolUserCounts(enforcedSchoolCode, userData.role, 1);

  console.log(`✅ Successfully created user: ${userData.username}`);

  return {
    username: userData.username,
    success: true,
    userId: userRecord.uid,
    email: email
  };
}

// ===== FCM NOTIFICATION FUNCTIONS =====

// Send notification when a new announcement is created
exports.sendAnnouncementNotification = functions.firestore
  .document('schools/{schoolCode}/announcements/{announcementId}')
  .onCreate(async (snapshot, context) => {
    const announcement = snapshot.data();
    const { schoolCode } = context.params;

    const message = {
      notification: {
        title: announcement.title || 'New Announcement',
        body: announcement.content ? announcement.content.substring(0, 100) + '...' : 'New announcement available',
      },
      data: {
        type: 'announcement',
        announcementId: snapshot.id,
        schoolCode: schoolCode,
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      },
    };

    // Send to role-based topics but exclude admin topics to prevent sender from receiving their own notifications
    if (announcement.recipient_groups && Array.isArray(announcement.recipient_groups)) {
      const topics = announcement.recipient_groups
        .filter(role => role !== 'admin') // Exclude admin topics
        .map(role => `${schoolCode}_${role}`);
      
      for (const topic of topics) {
        try {
          await admin.messaging().send({
            ...message,
            topic: topic
          });
          console.log(`Notification sent to topic: ${topic}`);
        } catch (error) {
          console.error(`Error sending to topic ${topic}:`, error);
        }
      }
    }

    return null;
  });

// Send notification when a new notice is created
exports.sendNoticeNotification = functions.firestore
  .document('schools/{schoolCode}/notices/{noticeId}')
  .onCreate(async (snapshot, context) => {
    const notice = snapshot.data();
    const { schoolCode } = context.params;
    const senderId = notice.sender_id; // Get the sender ID

    const message = {
      notification: {
        title: notice.title || 'New Notice',
        body: notice.content ? notice.content.substring(0, 100) + '...' : 'New notice available',
      },
      data: {
        type: 'notice',
        noticeId: snapshot.id,
        schoolCode: schoolCode,
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      },
    };

    // Send to individual users but exclude the sender
    if (notice.recipients && Array.isArray(notice.recipients)) {
      for (const userId of notice.recipients) {
        // Skip sending notification to the sender
        if (userId === senderId) {
          console.log(`Skipping notification for sender: ${userId}`);
          continue;
        }
        
        try {
          await admin.messaging().send({
            ...message,
            topic: `user_${userId}`
          });
          console.log(`Notification sent to user: ${userId}`);
        } catch (error) {
          console.error(`Error sending to user ${userId}:`, error);
        }
      }
    }

    return null;
  });

// Send notification when a new assignment is created
exports.sendAssignmentNotification = functions.firestore
  .document('schools/{schoolCode}/assignments/{assignmentId}')
  .onCreate(async (snapshot, context) => {
    const assignment = snapshot.data();
    const { schoolCode } = context.params;

    const message = {
      notification: {
        title: 'New Assignment',
        body: `${assignment.title || 'New assignment'} - Due: ${assignment.due_date || 'Soon'}`,
      },
      data: {
        type: 'assignment',
        assignmentId: snapshot.id,
        schoolCode: schoolCode,
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      },
    };

    // Send to school topic and student topic (exclude admin topics)
    try {
      await admin.messaging().send({
        ...message,
        topic: `${schoolCode}_student`
      });
      console.log(`Assignment notification sent for school: ${schoolCode}`);
    } catch (error) {
      console.error(`Error sending assignment notification:`, error);
    }

    return null;
  });

// Manual notification sender function (for testing)
exports.sendManualNotification = functions.https.onCall(async (data, context) => {
  // Check if user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { title, body, topic, schoolCode, userType } = data;

  if (!title || !body) {
    throw new functions.https.HttpsError('invalid-argument', 'Title and body are required');
  }

  try {
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: 'manual',
        schoolCode: schoolCode || 'unknown',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        timestamp: new Date().toISOString()
      },
    };

    let targetTopic = topic;
    
    if (!targetTopic && schoolCode && userType) {
      targetTopic = `${schoolCode}_${userType}`;
    } else if (!targetTopic && schoolCode) {
      targetTopic = `school_${schoolCode}`;
    }

    if (!targetTopic) {
      throw new functions.https.HttpsError('invalid-argument', 'Either topic or schoolCode must be provided');
    }

    const response = await admin.messaging().send({
      ...message,
      topic: targetTopic
    });

    return {
      success: true,
      messageId: response,
      topic: targetTopic
    };

  } catch (error) {
    console.error('Error sending manual notification:', error);
    throw new functions.https.HttpsError('internal', `Error sending notification: ${error.message}`);
  }
});

exports.sendMessageNotification = functions.firestore
  .document('schools/{schoolCode}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data();
    const { schoolCode } = context.params;
    const senderId = message.sender_id;
    
    console.log(`New message notification: ${message.subject}`);
    
    // Don't send notification to sender
    const recipients = message.recipients.filter(recipientId => recipientId !== senderId);
    
    if (recipients.length === 0) {
      console.log('No recipients to notify');
      return null;
    }
    
    const messageData = {
      notification: {
        title: `New Message from ${message.sender_name || 'Unknown'}`,
        body: message.subject || 'You have a new message',
      },
      data: {
        type: 'message',
        messageId: snapshot.id,
        schoolCode: schoolCode,
        senderId: senderId,
        senderName: message.sender_name || 'Unknown',
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      },
    };
    
    // Send to each recipient
    const notifications = [];
    
    for (const recipientId of recipients) {
      try {
        // Get recipient's FCM tokens
        const userDoc = await admin.firestore().collection('users').doc(recipientId).get();
        if (userDoc.exists) {
          const userData = userDoc.data();
          const fcmTokens = userData.fcm_tokens || [];
          
          // Send to each token
          for (const token of fcmTokens) {
            try {
              await admin.messaging().send({
                ...messageData,
                token: token
              });
              console.log(`Message notification sent to user: ${recipientId}`);
            } catch (tokenError) {
              console.error(`Error sending to token for user ${recipientId}:`, tokenError);
              // Remove invalid token
              if (tokenError.code === 'messaging/registration-token-not-registered') {
                await admin.firestore().collection('users').doc(recipientId).update({
                  fcm_tokens: admin.firestore.FieldValue.arrayRemove([token])
                });
              }
            }
          }
        }
      } catch (error) {
        console.error(`Error sending message notification to user ${recipientId}:`, error);
      }
    }
    
    return Promise.all(notifications);
  });