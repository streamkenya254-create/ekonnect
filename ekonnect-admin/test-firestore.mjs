import { initializeApp } from 'firebase/app'
import { getFirestore, doc, setDoc, getDoc } from 'firebase/firestore'

const firebaseConfig = {
  apiKey: 'AIzaSyDwUvaCqXQo0Pxduziir63SiLIIqvhrxso',
  authDomain: 'ekonnectapp.firebaseapp.com',
  projectId: 'ekonnectapp',
  storageBucket: 'ekonnectapp.firebasestorage.app',
  messagingSenderId: '365887153225',
  appId: '1:365887153225:web:70ee612c9024a60cc90b98',
  databaseURL: 'https://ekonnectapp-default-rtdb.firebaseio.com',
}

const app = initializeApp(firebaseConfig)
const db = getFirestore(app)

console.log('Testing Firestore read...')
const readPromise = getDoc(doc(db, '_test', 'ping'))
  .then(() => console.log('READ: success'))
  .catch(e => console.error('READ error:', e.code, e.message))

console.log('Testing Firestore write...')
const writePromise = setDoc(doc(db, '_test', 'ping'), { ok: true, ts: Date.now() })
  .then(() => console.log('WRITE: success'))
  .catch(e => console.error('WRITE error:', e.code, e.message))

const timeout = new Promise((_, reject) =>
  setTimeout(() => reject(new Error('TIMED OUT after 30s')), 30000)
)

Promise.race([Promise.all([readPromise, writePromise]), timeout])
  .then(() => { console.log('Done.'); process.exit(0) })
  .catch(e => { console.error(e.message); process.exit(1) })
