<?php
#**************************************************************************
#  openSIS is a free student information system for public and non-public 
#  schools from Open Solutions for Education, Inc. web: www.os4ed.com
#
#  openSIS is  web-based, open source, and comes packed with features that 
#  include student demographic info, scheduling, grade book, attendance, 
#  report cards, eligibility, transcripts, parent portal, 
#  student portal and more.   
#
#  Visit the openSIS web site at http://www.opensis.com to learn more.
#  If you have question regarding this system or the license, please send 
#  an email to info@os4ed.com.
#
#  This program is released under the terms of the GNU General Public License as  
#  published by the Free Software Foundation, version 2 of the License. 
#  See license.txt.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#***************************************************************************************
error_reporting(0);
class custom{
    public $customQuery = array();
    public $customQueryString = array();
    private $dbconncus = null;
    
    function __construct($mysql_database){
        $this->dbconncus = new mysqli(
            isset($_SESSION['server']) ? $_SESSION['server'] : '',
            isset($_SESSION['username']) ? $_SESSION['username'] : '',
            isset($_SESSION['password']) ? $_SESSION['password'] : '',
            $mysql_database,
            isset($_SESSION['port']) ? $_SESSION['port'] : 3306
        );    
    }
    
    function set($res, $table, $mysql_database) {
        $dbconncus = new mysqli(
            isset($_SESSION['server']) ? $_SESSION['server'] : '',
            isset($_SESSION['username']) ? $_SESSION['username'] : '',
            isset($_SESSION['password']) ? $_SESSION['password'] : '',
            $mysql_database,
            isset($_SESSION['port']) ? $_SESSION['port'] : 3306
        );    
        
        $result = $dbconncus->query($res);
        if (!$result) {
            die($dbconncus->error . ' at line CustomClass');
        }

        while($row = $result->fetch_assoc()) {	
            $this->customQuery[] = $row;
        }
        
        foreach($this->customQuery as $value){
            $str = "ALTER TABLE $table ADD " . $value['Field'] . " " . $value['Type'];
            if($value['Null'] == 'YES'){
                $str .= " NULL ";
            } else if($value['Null'] == 'NO'){
                $str .= " NOT NULL ";
            }
            if(!empty($value['Default'])){
                $str .= " DEFAULT '" . $value['Default'] . "' ";
            }
            $this->customQueryString[] = $str;
        }
    }
    
    function __destruct() {
        if ($this->dbconncus !== null) {
            $this->dbconncus->close();
        }
    }
}

 ?>